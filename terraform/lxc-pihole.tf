resource "proxmox_virtual_environment_container" "pihole" {
  description  = "Pihole DNS"
  node_name    = var.proxmox_node
  vm_id        = 200
  unprivileged = true
  started      = true

  features {
    nesting = true
  }

  initialization {
    hostname = "sentinel"

    ip_config {
      ipv4 {
        address = "192.168.178.4/24"
        gateway = "192.168.178.1"
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 4
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    type             = "debian"
  }

}
