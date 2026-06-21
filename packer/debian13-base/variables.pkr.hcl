variable "proxmox_url" {
  type        = string
  description = "URL API Proxmox, es. https://192.168.178.2:8006/api2/json"
}

variable "proxmox_token_id" {
  type        = string
  description = "Token ID nel formato user@realm!tokenname, es. packer@pve!packer"
  sensitive   = true
}

variable "proxmox_token_secret" {
  type        = string
  description = "Token secret"
  sensitive   = true
}

variable "proxmox_node" {
  type        = string
  default     = "houston"
  description = "Nome del nodo Proxmox"
}

variable "source_vm_id" {
  type        = number
  default     = 9000
  description = "ID del template base creato da upload-cloud-image.sh"
}

variable "target_vm_id" {
  type        = number
  default     = 9001
  description = "ID del template finale prodotto da Packer"
}

variable "ssh_private_key_file" {
  type        = string
  default     = "~/.ssh/id_ed25519"
  description = "Chiave privata corrispondente alla pubblica usata in upload-cloud-image.sh"
}


