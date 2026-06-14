# LXC "vanguard" — Smallstep step-ca
#
# Network-wide private Certificate Authority (Root + Intermediate) exposing an
# ACME endpoint. cert-manager inside k3s and any other host on the LAN request
# certificates from here. The CA lives OUTSIDE the cluster on purpose, so its
# trust is not tied to k3s' lifecycle.
#
# IP .5  | vm_id 201 | hostname "vanguard"

resource "proxmox_virtual_environment_container" "stepca" {
  description  = "Smallstep step-ca — network private CA (ACME)"
  node_name    = var.proxmox_node
  vm_id        = 201
  unprivileged = true
  started      = true

  features {
    nesting = true
  }

  initialization {
    hostname = "vanguard"

    ip_config {
      ipv4 {
        address = "192.168.178.5/24"
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
    dedicated = 512 # step-ca is light; 512MB is comfortable
  }

  disk {
    datastore_id = "nvme"
    size         = 8
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
