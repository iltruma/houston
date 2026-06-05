# Fase 1b: Configurazione Rete

## Schema Rete

```
Internet
   │
   ▼
┌──────────┐
│  Router   │  192.168.178.1 (Gateway + DHCP per i client)
└────┬─────┘
     │
     ├── 192.168.178.2   houston   Proxmox VE (host)
     ├── 192.168.178.3   iss       VM   k3s single-node
     ├── 192.168.178.4   sentinel  LXC  Pi-hole (DNS)
     ├── 192.168.178.5   vanguard  LXC  step-ca (CA di rete)
     │
     └── 192.168.178.x   Altri dispositivi (DHCP dal router)
```

## Configurazione Bridge di Rete su Proxmox

Il file `/etc/network/interfaces` di Proxmox dovrebbe essere:

```
auto lo
iface lo inet loopback

iface enp1s0 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.178.2/24
    gateway 192.168.178.1
    bridge-ports enp1s0
    bridge-stp off
    bridge-fd 0
```

> `vmbr0` è il bridge Linux che permette a VM e container di accedere alla rete fisica.
> `enp1s0` è il nome dell'interfaccia fisica: **da verificare** sul tuo hardware (`ip link`).

## IP Statici

Gli host dell'homelab hanno IP statici (assegnati da Terraform/Proxmox, non via DHCP)
per stabilità. I client generici prendono l'IP dal DHCP del router.

| Host       | Ruolo                      | Tipo | IP            |
|------------|----------------------------|------|---------------|
| `houston`  | Hypervisor Proxmox VE      | host | 192.168.178.2 |
| `iss`      | Cluster k3s (single-node)  | VM   | 192.168.178.3 |
| `sentinel` | Pi-hole (DNS + adlists)    | LXC  | 192.168.178.4 |
| `vanguard` | step-ca (CA di rete, ACME) | LXC  | 192.168.178.5 |

## DNS

### Prima di Pi-hole
Il DNS punta al router: `192.168.178.1`

### Dopo Pi-hole attivo
1. Configurare il router per usare `192.168.178.4` (sentinel) come DNS primario,
   oppure distribuirlo via DHCP a tutti i client.
2. In Pi-hole, impostare l'upstream DNS (es. `1.1.1.1`, `8.8.8.8` — già in
   `setupVars.conf` del playbook).

## Firewall (opzionale)

Proxmox ha un firewall integrato. Per l'homelab locale si può lasciare disattivato,
ma se si vuole abilitarlo le regole minime per il nodo sono:

```
# Datacenter → Firewall → Options → Firewall: Yes
# Allow SSH (22)
# Allow Web UI (8006)
# Allow ICMP (ping)
```

## DNS locale personalizzato (via Pi-hole)

I record DNS locali sono gestiti **dichiarativamente** dal playbook
`pihole-setup.yml` (variabile `pihole_dns_records` in
`ansible/group_vars/all/vars.yml`), sul dominio interno **`.internal`**:

```
houston.internal    → 192.168.178.2
iss.internal        → 192.168.178.3
sentinel.internal   → 192.168.178.4
vanguard.internal   → 192.168.178.5
```

> Il dominio `.internal` è lo standard de-facto per le reti private (riserva ICANN
> proposta) ed evita i problemi di *DNS rebind protection* dei router domestici
> (es. Fritz!Box) che bloccano risposte con IP privati su TLD sconosciuti.
> I record dei servizi k8s (es. `argocd.internal`) si aggiungeranno con gli sprint
> di Fase 1+ tramite Ingress/cert-manager.

## Verifica

- [ ] Proxmox raggiungibile via `ping 192.168.178.2`
- [ ] VM e LXC hanno connettività internet
- [ ] Risoluzione DNS funzionante da tutti i nodi (`dig iss.internal @192.168.178.4`)
- [ ] Dispositivi sulla rete riescono ad accedere alle risorse dell'homelab
