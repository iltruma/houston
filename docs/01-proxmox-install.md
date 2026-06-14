# Fase 1: Installazione Proxmox VE

## Prerequisiti

- Dell Optiplex 3050 (i5-6500T, 16GB RAM)
- 2 dischi: SATA SSD 500GB (`/dev/sda`) + NVMe 500GB (`/dev/nvme0n1`)
- Chiavetta USB >= 2GB
- Monitor e tastiera per installazione iniziale
- Cavo Ethernet collegato alla rete locale

## 0. BIOS — SATA Operation su AHCI (importante)

Sui Dell Optiplex la voce *SATA Operation* è spesso impostata su **"RAID On"**
(Intel RST). In questa modalità l'NVMe viene "remappato" dietro il controller
Intel e **Linux non lo vede**: in `dmesg` compare `Found 1 remapped NVMe devices`,
`lspci` non trova il controller NVMe e `lsblk` non mostra `/dev/nvme0n1`.

Prima di installare:

1. Riavvia e premi **F2** per entrare nel Setup BIOS.
2. *System Configuration → SATA Operation* → seleziona **AHCI**.
3. Salva ed esci (**F10**).

> AHCI espone SATA e NVMe in modo nativo: il kernel vede `sda` (driver `ahci`)
> e `nvme0n1` (driver `nvme`).
> ⚠️ Cambiare questa voce rende non avviabile un OS installato in modalità RAID:
> impostala **prima** di installare Proxmox.

## 1. Scaricare Proxmox VE ISO

Scaricare l'ultima versione stabile da: https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso

## 2. Creare USB Bootabile

```bash
# Linux/Mac
sudo dd bs=4M if=proxmox-ve_*.iso of=/dev/sdX status=progress

# Oppure usare balenaEtcher (Windows/Mac/Linux)
```

## 3. Installazione

1. Inserire USB e avviare il Dell Optiplex
2. Premere F12 per il boot menu, selezionare USB
3. Selezionare "Install Proxmox VE (Graphical)"
4. Accettare EULA
5. Selezionare il disco target: il **SATA SSD** (`/dev/sda`), **non** l'NVMe.
   - Filesystem: **ext4** (no ZFS — vedi [05-storage.md](05-storage.md)).
   - Aprire **Options** (opzioni avanzate del partizionamento) e impostare:

     | Opzione | Valore | Perché |
     |---|---|---|
     | `swapsize` | 8 | swap (16GB RAM) |
     | `maxroot` | 50 | dimensione di `pve-root` |
     | `maxvz` | 0 | **niente `local-lvm` sul SATA**: lo spazio resta libero nel VG `pve` per crearci dopo `sata-media` e `sata-backup` |

   > ⚠️ L'NVMe **non** va toccato dall'installer: lo configuriamo a mano dopo
   > (sezione 5) come thin pool dedicato a VM e PV k3s.
6. Configurazione locale (Country: Italy, Timezone: Europe/Rome, Keyboard: Italian)
7. Password root e email amministratore
8. Configurazione rete:
   - Management Interface: la porta Ethernet (es. `enp1s0`)
   - Hostname: `houston.internal`
   - IP Address: `192.168.178.2/24`
   - Gateway: `192.168.178.1`
   - DNS Server: `192.168.178.1` (temporaneo, poi sarà Pi-hole su `.4`)

## 4. Post-Installazione

### Accesso alla Web UI

Dopo il reboot, accedere a: `https://192.168.178.2:8006`
- Username: `root`
- Realm: `Linux PAM`

### Abilitare SSH per Ansible (se non già attivo)

```bash
systemctl status ssh
# se non gira:
systemctl enable --now ssh
```

Dalla workstation, copia la chiave pubblica:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.178.2
```

### Lanciare il playbook di setup

Tutto il resto (repo apt, upgrade, popup subscription, thin pool NVMe, LV su SATA,
registrazione storage Proxmox, node_exporter) è in `ansible/playbooks/houston-setup.yml`.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/houston-setup.yml
```

Il playbook è **idempotente**: può girare più volte senza effetti collaterali.

Al termine, `pvesm status` deve mostrare quattro storage:

| Nome | Tipo | Cosa contiene |
|---|---|---|
| `local` | dir | ISO, template LXC (su SATA `pve-root`) |
| `nvme` | lvmthin | root disk VM/LXC + immagini (su NVMe) |
| `sata-media` | dir | disco dati Jellyfin/download (su SATA) |
| `sata-backup` | dir | target vzdump — S6 Backup/DR (su SATA) |

> Layout completo con tagli di spazio: [05-storage.md](05-storage.md).

## 5. Configurazione Storage

## 5. Scaricare template container

```bash
# Template Debian 13 per LXC (quello referenziato dai file Terraform)
pveam update
pveam available --section system | grep debian
pveam download local debian-13-standard_13.1-2_amd64.tar.zst
```

## 6. Abilitare IOMMU (opzionale, per PCIe passthrough futuro)

Modificare GRUB:
```bash
# In /etc/default/grub, aggiungere a GRUB_CMDLINE_LINUX_DEFAULT:
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"

update-grub
reboot
```

## Verifica

- [ ] Web UI accessibile su `https://192.168.178.2:8006`
- [ ] `pveversion` mostra la versione corretta
- [ ] `apt update` funziona senza errori
- [ ] OS installato sul **SATA** (`lsblk` mostra `pve` su `/dev/sda`)
- [ ] Storage visibili: `local`, `nvme`, `sata-media`, `sata-backup`
- [ ] `/mnt/sata-media` e `/mnt/sata-backup` montati (anche dopo reboot)
- [ ] Template container scaricato
