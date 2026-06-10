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
  clone_vm_id  = var.source_vm_id
  full_clone   = true
  qemu_agent   = true

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

  # Packer si connette come 'debian' (utente default del cloud image)
  communicator         = "ssh"
  ssh_username         = "debian"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "5m"

  # --- Output ---
  template_name        = "debian13-base"
  template_description = "Debian 13 Trixie — base template. qemu-agent, ansible user, SSH hardened."
}

build {
  name    = "debian13-base"
  sources = ["source.proxmox-clone.debian13"]

  # 0. Attendi che cloud-init finisca prima di usare apt.
  #    Al primo boot cloud-init tiene dpkg occupato — senza questo wait
  #    i provisioner successivi falliscono con "dpkg lock" error.
  provisioner "shell" {
    inline           = ["sudo cloud-init status --wait"]
    valid_exit_codes = [0, 2]
  }

  # 1. Pacchetti base comuni a tutti i playbook Ansible.
  #    --no-install-recommends mantiene il template minimale.
  provisioner "shell" {
    inline = [
      "sudo apt-get update -qq",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends qemu-guest-agent python3 curl ca-certificates gnupg",
      "sudo systemctl enable fstrim.timer",
    ]
  }

  # 2. Configurazione sistema: timezone, locale, datasource cloud-init.
  #    Il datasource list evita timeout al boot cercando AWS/GCE/Azure
  #    su una rete domestica — Proxmox usa solo NoCloud e ConfigDrive.
  provisioner "shell" {
    inline = [
      "sudo timedatectl set-timezone Europe/Rome",
      "sudo sed -i 's/^# it_IT.UTF-8 UTF-8/it_IT.UTF-8 UTF-8/' /etc/locale.gen",
      "sudo locale-gen",
      "echo 'LANG=it_IT.UTF-8' | sudo tee /etc/default/locale",
      "sudo mkdir -p /etc/cloud/cloud.cfg.d",
      "echo 'datasource_list: [NoCloud, ConfigDrive, None]' | sudo tee /etc/cloud/cloud.cfg.d/99-proxmox.cfg",
    ]
  }

  # 3. SSH hardening via drop-in file.
  #    Scrivere in sshd_config.d/ è più robusto del sed su sshd_config:
  #    le direttive qui hanno precedenza e non dipendono da regex su righe commentate.
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/ssh/sshd_config.d",
      "printf 'PasswordAuthentication no\nPermitRootLogin no\nPubkeyAuthentication yes\nX11Forwarding no\nAllowTcpForwarding no\nMaxAuthTries 3\nLoginGraceTime 30\n' | sudo tee /etc/ssh/sshd_config.d/99-hardening.conf",
    ]
  }

  # 4. Utente 'ansible' dedicato con sudo NOPASSWD.
  #    Nessuna SSH key qui: cloud-init la inietta al primo boot dalla
  #    configurazione Terraform (initialization.user_account).
  provisioner "shell" {
    inline = [
      "sudo useradd -m -s /bin/bash ansible",
      "sudo usermod -aG sudo ansible",
      "echo 'ansible ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ansible",
      "sudo chmod 0440 /etc/sudoers.d/ansible",
      "sudo mkdir -p /home/ansible/.ssh",
      "sudo chmod 700 /home/ansible/.ssh",
      "sudo chown -R ansible:ansible /home/ansible/.ssh",
    ]
  }

  # 5. Cleanup template: cloud-init clean resetta lo stato per il primo boot
  #    della VM clonata; machine-id a zero garantisce ID univoci per ogni clone.
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
