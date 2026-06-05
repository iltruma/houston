# Fase 1: Installazione Proxmox VE

## Prerequisiti

- Dell Optiplex 3050 (i5-6500T, 16GB RAM, 500GB SSD)
- Chiavetta USB >= 2GB
- Monitor e tastiera per installazione iniziale
- Cavo Ethernet collegato alla rete locale

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
5. Selezionare il disco target (500GB SSD)
   - Filesystem: **ext4** (più semplice) o **ZFS** (se si vuole snapshot nativi)
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

### Rimuovere Enterprise Repository

```bash
# Commentare o rimuovere il repo enterprise
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
```

### Aggiungere No-Subscription Repository

```bash
# Debian 13 "trixie" → Proxmox VE 9.x
echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
```

> **da verificare**: su Proxmox VE 9 i repository usano il nuovo formato deb822
> (`/etc/apt/sources.list.d/*.sources`) invece dei classici `.list`. Controlla
> con `ls /etc/apt/sources.list.d/` quale formato è presente sulla tua installazione.

### Aggiornare il sistema

```bash
apt update && apt full-upgrade -y
reboot
```

### Rimuovere popup subscription (opzionale)

```bash
sed -Ezi.bak "s/(Ext\.Msg\.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy.service
```

## 5. Configurazione Storage

Di default Proxmox crea:
- `local` — per ISO, template, backup
- `local-lvm` — per dischi VM e container

Verificare con:
```bash
pvesm status
```

### Scaricare template container

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
- [ ] Storage `local` e `local-lvm` visibili
- [ ] Template container scaricato
