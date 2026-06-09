resource "proxmox_virtual_environment_vm" "k3s" {
  name      = "iss"
  node_name = var.proxmox_node
  vm_id     = 100

  stop_on_destroy = true

  agent {
    enabled = true
  }

  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "local-lvm"
    size         = 200
    interface    = "scsi0"
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.178.3/24"
        gateway = "192.168.178.1"
      }
    }
    user_account {
      username = "debian"
      keys     = [var.ssh_public_key]
    }
  }
}
