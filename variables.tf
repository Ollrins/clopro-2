variable "service_account_key_file" {
  type        = string
  default     = "/home/Ollrins/key.json"
}

variable "ssh_public_key" {
  type        = string
  default     = "/home/Ollrins/key.pub"
}

variable "ssh_user" {
  type        = string
  default     = "Ollrins"
}

variable "cloud_id" {
  type        = string
}

variable "folder_id" {
  type        = string
}

variable "zone" {
  type        = string
  default     = "ru-central1-b"
}

# Ключи для загрузки объекта в существующий бакет
variable "storage_access_key" {
  description = "Storage Access Key"
  type        = string
}

variable "storage_secret_key" {
  description = "Storage Secret Key"
  sensitive   = true
  type        = string
}
