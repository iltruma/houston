#!/usr/bin/env bash
# Eseguire UNA VOLTA su houston come root.
# Crea il template Proxmox grezzo (ID 9000) dal cloud image Debian 13.
# Packer clona questo template e produce il template finale (ID 9001).
#
# Uso: ./upload-cloud-image.sh [vm_id] [storage] [ssh_public_key] [disk_size]
# Es:  ./upload-cloud-image.sh 9000 local-lvm ~/.ssh/id_ed25519.pub 20G

set -euo pipefail

VM_ID="${1:-9000}"
VM_NAME="debian13-cloud-raw"
STORAGE="${2:-local-lvm}"
SSH_KEY_FILE="${3:-$HOME/.ssh/id_ed25519.pub}"
DISK_SIZE="${4:-20G}"

IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
IMAGE_FILE="/tmp/debian-13-genericcloud-amd64.qcow2"

if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo "ERRORE: chiave SSH pubblica non trovata: $SSH_KEY_FILE"
  echo "Uso: $0 [vm_id] [storage] [ssh_public_key]"
  exit 1
fi

if qm status "$VM_ID" &>/dev/null; then
  echo "ERRORE: VM/template $VM_ID esiste già. Rimuoverla prima con: qm destroy $VM_ID"
  exit 1
fi

echo "==> Download Debian 13 genericcloud image..."
wget -q --show-progress "$IMAGE_URL" -O "$IMAGE_FILE"

echo "==> Installazione qemu-guest-agent nell'immagine (richiede libguestfs-tools)..."
if ! command -v virt-customize &>/dev/null; then
  echo "ERRORE: virt-customize non trovato. Installa con: apt install libguestfs-tools"
  exit 1
fi
virt-customize -a "$IMAGE_FILE" \
  --install qemu-guest-agent \
  --truncate /etc/machine-id

echo "==> Creazione VM $VM_ID ($VM_NAME)..."
qm create "$VM_ID" \
  --name "$VM_NAME" \
  --memory 1024 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --serial0 socket \
  --vga serial0 \
  --ostype l26 \
  --agent enabled=1

echo "==> Import disco..."
qm importdisk "$VM_ID" "$IMAGE_FILE" "$STORAGE" --format raw

echo "==> Configurazione VM..."
qm set "$VM_ID" \
  --virtio0 "$STORAGE:vm-$VM_ID-disk-0,discard=on" \
  --ide2 "$STORAGE:cloudinit" \
  --boot order=virtio0 \
  --ipconfig0 ip=dhcp \
  --ciuser debian \
  --sshkeys "$SSH_KEY_FILE"

echo "==> Resize disco a ${DISK_SIZE}..."
qm resize "$VM_ID" virtio0 "$DISK_SIZE"

echo "==> Conversione in template..."
qm template "$VM_ID"

rm -f "$IMAGE_FILE"

echo ""
echo "Template $VM_ID ($VM_NAME) pronto."
echo "Ora esegui dalla workstation: packer build -var-file=variables.pkrvars.hcl ."
