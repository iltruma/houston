# Fase 1b: Configurazione Rete

## Schema Rete

```
Internet
   │
   ▼
┌──────────┐
│  Router   │  192.168.1.1 (Gateway + DHCP temporaneo)
└────┬─────┘
     │
     ├── 192.168.1.100  Proxmox (host)
     ├── 192.168.1.101  VM k3s
     ├── 192.168.1.2    LXC Pihole (DNS)
     │
     └── 192.168.1.x    Altri dispositivi (DHCP)
```

## Configurazione Bridge di Rete su Proxmox

Il file `/etc/network/interfaces` di Proxmox dovrebbe essere:

```
auto lo
iface lo inet loopback

iface enp1s0 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.1.100/24
    gateway 192.168.1.1
    bridge-ports enp1s0
    bridge-stp off
    bridge-fd 0
```

> `vmbr0` è il bridge Linux che permette a VM e container di accedere alla rete fisica.

## IP Statici

Tutti gli IP sono assegnati staticamente (non via DHCP) per stabilità:

| Host | IP | MAC (opzionale) |
|------|-----|-----------------|
| Proxmox | 192.168.1.100 | - |
| k3s VM | 192.168.1.101 | - |
| Pihole LXC | 192.168.1.2 | - |

## DNS

### Prima di Pihole
Il DNS punta al router: `192.168.1.1`

### Dopo Pihole attivo
1. Configurare il router per usare `192.168.1.2` come DNS primario
2. Oppure configurare il DHCP del router per distribuire `192.168.1.2` come DNS
3. In Pihole, impostare upstream DNS (es. `1.1.1.1`, `8.8.8.8`)

## Firewall (opzionale)

Proxmox ha un firewall integrato. Per l'homelab locale si può lasciare disattivato, ma se si vuole:

```bash
# Abilitare firewall a livello datacenter
# Datacenter → Firewall → Options → Firewall: Yes

# Regole minime per il nodo
# Allow SSH
# Allow Web UI (8006)
# Allow ICMP (ping)
```

## DNS locale personalizzato (via Pihole)

Dopo che Pihole è attivo, aggiungere record DNS locali:

```
pve.local         → 192.168.1.100
k3s.local         → 192.168.1.101
pihole.local      → 192.168.1.2
argocd.local      → 192.168.1.101
headroom.local    → 192.168.1.101
```

Questi record si aggiungono in Pihole → Local DNS → DNS Records.

## Verifica

- [ ] Proxmox raggiungibile via `ping 192.168.1.100`
- [ ] VM e LXC hanno connettività internet
- [ ] Risoluzione DNS funzionante da tutti i nodi
- [ ] Dispositivi sulla rete riescono ad accedere alle risorse dell'homelab
