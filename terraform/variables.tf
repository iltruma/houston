variable "proxmox_api_token" {
  description = "API token per Proxmox (formato: user@realm!tokenname=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Nome del nodo Proxmox"
  type        = string
  default     = "houston"
}

variable "ssh_public_key" {
  description = "Chiave SSH pubblica per accedere alle VM"
  type        = string
}
