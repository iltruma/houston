resource "proxmox_virtual_environment_vm" "k3s" {
  name      = "iss"
  node_name = var.proxmox_node
  vm_id     = 100

  stop_on_destroy = true

  agent {
    enabled = true
  }

  clone {
    vm_id = 9001
    full  = true
  }

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  # Disco root (vda): clonato dal template (20G) ed espanso a 40G per OS +
  # immagini container + dati k3s di sistema. Su NVMe per I/O veloce.
  disk {
    datastore_id = "nvme"
    interface    = "virtio0"
    size         = 40
  }

  # Disco dati (vdb): nuovo, dedicato ai PersistentVolume di k3s
  # (Prometheus, Grafana, …). Ansible lo formatta e monta su /mnt/k3s-data.
  # Vedi docs/05-storage.md.
  disk {
    datastore_id = "nvme"
    interface    = "virtio1"
    size         = 250
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    # Disco cloud-init su NVMe (il default del provider sarebbe local-lvm,
    # storage che non esiste piu' dopo il rebuild a due dischi).
    datastore_id = "nvme"

    ip_config {
      ipv4 {
        address = "192.168.178.3/24"
        gateway = "192.168.178.1"
      }
    }
    user_account {
      username = "ansible"
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
