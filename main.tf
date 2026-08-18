# ==========================================
# 1. Создание VPC и подсетей
# ==========================================
resource "yandex_vpc_network" "main" {
  name = "homework-network"
}

resource "yandex_vpc_subnet" "public" {
  name           = "public"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

# ==========================================
# 2. Загрузка картинки в существующий бакет
# ==========================================
resource "yandex_storage_object" "hw_image" {
  bucket       = "dev-oll"
  key          = "avatar.jpg" # Убедитесь, что имя файла совпадает с тем, что вы загрузили
  source       = "${path.module}/avatar.jpg"
  access_key   = var.storage_access_key
  secret_key   = var.storage_secret_key
  content_type = "image/jpeg"
}

# ==========================================
# 3. Security Group для Instance Group
# ==========================================
resource "yandex_vpc_security_group" "ig_sg" {
  name        = "ig-lamp-sg"
  network_id  = yandex_vpc_network.main.id
  description = "SG for LAMP Instance Group"

  ingress {
    protocol       = "TCP"
    description    = "Allow HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 80
    to_port        = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 22
    to_port        = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all egress"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# 4. Instance Group с LAMP
# ==========================================
locals {
  image_url = "https://dev-oll.storage.yandexcloud.net/avatar.jpg"
  
  # Используем write_files для гарантированного создания файла
  user_data = <<-EOT
    #cloud-config
    users:
      - name: ${var.ssh_user}
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys:
          - ${file(var.ssh_public_key)}
    packages:
      - apache2
    write_files:
      - path: /var/www/html/index.html
        owner: root:root
        permissions: '0644'
        content: |
          <!DOCTYPE html>
          <html>
          <head><title>LAMP Instance Group</title></head>
          <body style="text-align: center; font-family: Arial, sans-serif;">
            <h1>LAMP Instance Group работает!</h1>
            <p>Картинка загружается напрямую из Object Storage:</p>
            <img src="${local.image_url}" width="400" alt="YC Image" style="border: 2px solid #333; border-radius: 8px;">
          </body>
          </html>
    runcmd:
      - systemctl enable --now apache2
      - systemctl restart apache2
  EOT
}

resource "yandex_compute_instance_group" "lamp_group" {
  name               = "lamp-instance-group"
  folder_id          = var.folder_id
  service_account_id = jsondecode(file(var.service_account_key_file)).service_account_id

  instance_template {
    platform_id = "standard-v3"
    resources {
      cores         = 2
      memory        = 2
      core_fraction = 20
    }

    boot_disk {
      initialize_params {
        image_id = "fd827b91d99psvq5fjit"
        size     = 15
        type     = "network-ssd"
      }
    }

    network_interface {
      network_id         = yandex_vpc_network.main.id
      subnet_ids         = [yandex_vpc_subnet.public.id]
      security_group_ids = [yandex_vpc_security_group.ig_sg.id]
    }

    metadata = {
      user-data = local.user_data
    }
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    zones = [var.zone]
  }

  deploy_policy {
    max_unavailable = 1
    max_creating    = 1
    max_expansion   = 1
    max_deleting    = 1
  }

  load_balancer {
    target_group_name        = "lamp-target-group"
    target_group_description = "Target group for LAMP IG"
  }

  health_check {
    http_options {
      port = 80
      path = "/"
    }
  }
}

# ==========================================
# 5. Network Load Balancer
# ==========================================
resource "yandex_lb_network_load_balancer" "nlb" {
  name = "network-lb-lamp"

  listener {
    name        = "http-listener"
    port        = 80
    target_port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.lamp_group.load_balancer[0].target_group_id
    
    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

# ==========================================
# 6. Outputs
# ==========================================
output "image_public_url" {
  value = local.image_url
}

output "nlb_external_ip" {
  value = [for l in yandex_lb_network_load_balancer.nlb.listener : [for e in l.external_address_spec : e.address][0]][0]
}
