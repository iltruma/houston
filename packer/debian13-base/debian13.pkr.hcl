packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

source "proxmox-clone" "debian13" {
  # --- Connessione Proxmox ---
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # --- Clone: eredita cloud-init (DHCP + SSH key) dal template base ---
  clone_vm_id = var.source_vm_id
  full_clone  = true

  # --- VM temporanea di build ---
  vm_id   = var.target_vm_id
  vm_name = "debian13-base-build"
  memory  = 1024
  cores   = 2
  sockets = 1
  onboot  = false

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # --- SSH: Packer si connette come utente 'debian' (default cloud image) ---
  communicator         = "ssh"
  ssh_username         = "debian"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "5m"

  # --- Output ---
  template_name        = "debian13-base"
  template_description = "Debian 13 Trixie — qemu-guest-agent, SSH hardened. Built with Packer."
}

build {
  name    = "debian13-base"
  sources = ["source.proxmox-clone.debian13"]

  # 1. qemu-guest-agent: permette a Proxmox di comunicare con la VM
  #    (IP, snapshot consistent, graceful shutdown)
  provisioner "shell" {
    inline = [
      "sudo apt-get update -qq",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent",
      "sudo systemctl enable qemu-guest-agent",
    ]
  }

  # 2. SSH hardening
  provisioner "shell" {
    inline = [
      "sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config",
    ]
  }

  # 3. Cleanup template: ogni VM clonata deve avere machine-id univoco.
  #    truncate a zero + symlink è il metodo corretto su Debian (man machine-id).
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo apt-get autoremove -y",
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id",
      "sudo sync",
    ]
  }
}
