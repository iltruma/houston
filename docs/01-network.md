# Rete

Configurazione di rete per Astra. Topologia, bridge, firewall, DNS ricorsivo.

## Schema rete

```
Internet
   │
   ▼
┌──────────┐
│  iris    │  192.168.178.1 (Router Fritz!Box — Gateway + DHCP per i client)
└────┬─────┘
     │
     ├── 192.168.178.2   nebula   NixOS baremetal
     │                            ├─ Technitium DNS (servizio, :53)
     │                            ├─ k3s API (servizio, :6443)
     │                            └─ Traefik ingress (:80, :443)
     │
     └── 192.168.178.x   Altri dispositivi (DHCP dal router)
```

> **Cambiamento post-migrazione**: tutto gira sull'host `nebula` (.2). Non
> esistono più VM/LXC con IP separati. I servizi k3s rispondono su `.2:6443`,
> Technitium su `.2:53`, Traefik su `.2:80/443`.

## Bridge br0

Configurazione in [`hosts/nebula/networking.nix`](../hosts/nebula/networking.nix):

```nix
networking.bridges.br0.interfaces = [ "enp1s0" ];
networking.interfaces.br0.ipv4.addresses = [
  { address = "192.168.178.2"; prefixLength = 24; }
];
```

Topologia: `enp1s0` (fisica) → `br0` (bridge) → IP host. Il bridge è
trasparente, equivalente a un cavo diretto. Modello analogo al `vmbr0` di
Proxmox, ma non c'è più Proxmox.

Per ora `br0` ha solo l'host come membro. Se in futuro aggiungi container o
VM, basta attaccare la loro interfaccia a `br0` e avranno IP nella LAN.

## IP statici

| Host       | Ruolo                      | Tipo | IP            |
|------------|----------------------------|------|---------------|
| `iris`     | Router Fritz!Box (gateway) | hw   | 192.168.178.1 |
| `nebula`  | NixOS + k3s + DNS + ingress | host | 192.168.178.2 |

I client generici prendono IP dal DHCP del router. Il Fritz!Box ha una
reservation DHCP per `nebula` basata sul MAC di `enp1s0` (opzionale, ma
utile se vuoi che `.2` sia sempre lui).

## Firewall

Default NixOS: drop tutto tranne porte esplicite. Configurazione in
[`hosts/nebula/networking.nix`](../hosts/nebula/networking.nix):

```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [
    22    # SSH
    53    # DNS (Technitium)
    80    # HTTP (Traefik)
    443   # HTTPS (Traefik)
    6443  # k3s API (LAN only)
    10250 # kubelet metrics
  ];
  allowedUDPPorts = [
    53    # DNS (Technitium)
  ];
};
```

**Porte aperte**:

| Porta | Servizio | Scope |
|-------|----------|-------|
| 22/tcp | SSH | LAN |
| 53/tcp+udp | Technitium DNS | LAN |
| 80/tcp | Traefik HTTP (redirect → HTTPS) | LAN |
| 443/tcp | Traefik HTTPS | LAN |
| 6443/tcp | k3s API server | LAN (workstation) |
| 10250/tcp | kubelet metrics | localhost (k3s interno) |

**Porte chiuse** (perché non servono o non devono essere esposte):
- 8006 (Proxmox UI): non c'è più Proxmox
- 5380/53443 (Technitium web UI): solo localhost, accesso via SSH tunnel
- 53 da Internet: il firewall del Fritz!Box blocca già, ma per sicurezza NixOS
  non espone nulla fuori dalla LAN

## DNS ricorsivo

Prima della migrazione: il DNS puntava al router (192.168.178.1) o a Pi-hole.
Dopo: il DNS primario per i client della LAN è **Technitium su 192.168.178.2**.

Configurazione Technitium (via web UI dopo install, vedi
[04-dns-technitium.md](04-dns-technitium.md)):

- **Zona autoritativa**: `lab.paroparo.it` con record wildcard
  `*.lab.paroparo.it → 192.168.178.2`
- **Split horizon**: per `lab.paroparo.it`, risponde dalla zona locale; per
  tutto il resto, delega agli upstream DoH (Cloudflare 1.1.1.1, Quad9 9.9.9.9)
- **Blocklist**: Steven Black + OISD (opzionale)

Per fare puntare i client a Technitium:
1. Configurare il router Fritz!Box per distribuire `192.168.178.2` come DNS
   primario via DHCP
2. Oppure configurare manualmente i client (workstation, dispositivi IoT, ecc.)

## DNS interno per pod k8s

I pod k8s usano CoreDNS bundled di k3s, configurato per delegare a Technitium
per la zona `lab.paroparo.it`. Configurazione in `modules/k3s.nix`:

```nix
environment.etc."k3s/coredns-custom.yaml".text = ''
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: coredns
    namespace: kube-system
  data:
    Corefile: |
      .:53 { ... forward . 192.168.178.2:53 ... }
      lab.paroparo.it:53 { ... forward . 192.168.178.2:53 ... }
'';
```

Il file si chiama `coredns-custom.yaml` (nome del file) ma il ConfigMap
Kubernetes ha `name: coredns` — nome esatto che k3s usa per override del
Corefile di default. È in `/var/lib/rancher/k3s/server/manifests/00-coredns-custom.yaml`
(symlink via `systemd.tmpfiles.rules`). k3s lo applica al boot con prefisso
`00-` PRIMA del suo CoreDNS bundled, che riconosce e usa il Corefile custom.

## Verifica

```bash
# Da workstation sulla LAN
ping 192.168.178.2                       # nebula risponde
ssh root@192.168.178.2                   # SSH funziona
dig @192.168.178.2 lab.paroparo.it       # DNS split-horizon funziona
dig @192.168.178.2 uptime.lab.paroparo.it # wildcard → 192.168.178.2
curl -v https://uptime.lab.paroparo.it   # Traefik + cert-manager

# Da nebula stesso
ip link show br0                          # bridge up
ip addr show br0                          # IP 192.168.178.2
ss -tlnp | grep -E ':(22|53|80|443|6443)' # porte in ascolto
```

## Piano B: VLAN con MikroTik hEX S (Fase 5)

Prerequisito hardware:
- **MikroTik hEX S 2025** (~69€) — router/gateway principale
- **MikroTik cAP ax** (~129€) — access point WiFi 6, gestito via CAPsMAN dall'hEX S
- Fritz!Box 3490 in modalità PPPoE passthrough (bridge VDSL puro)

### Topologia

```
Internet
    │
Fritz!Box 3490 (bridge VDSL — solo modem, gestisce tag VLAN 100 Aruba)
    │ Ethernet
    ▼
hEX S (PPPoE, routing inter-VLAN, DHCP, firewall, WireGuard ingress, CAPsMAN)
    ├── Ether1: WAN — PPPoE Aruba (user: aruba, pass: aruba)
    ├── Ether2: trunk 802.1Q → nebula (enp1s0)
    ├── Ether3: access VLAN 10 → workstation admin
    ├── Ether4: access VLAN 20 → device cablati altri utenti
    └── Ether5: trunk 802.1Q → cAP ax (+ injector PoE 802.3af)
                               ├── SSID "home"    → VLAN 10
                               ├── SSID "family"  → VLAN 20
                               └── SSID "guest"   → VLAN 30
```

> ⚠️ **Alimentazione cAP ax**: usare l'alimentatore diretto incluso nella
> confezione. Il PoE passivo dell'hEX S (tensione fissa, senza negoziazione
> 802.3af/at) potrebbe danneggiare il cAP ax se fuori range.

### Schema VLAN

| VLAN | Subnet | Gateway | Ospita | Accesso |
|------|--------|---------|--------|---------|
| 10 — Trusted | `10.10.0.0/24` | `10.10.0.1` | nebula (`10.10.0.2`), workstation admin | tutto |
| 20 — Home | `10.20.0.0/24` | `10.20.0.1` | PC/telefoni altri utenti di casa | Internet + nebula :80/443; no SSH, no k3s API |
| 30 — IoT/Guest | `10.30.0.0/24` | `10.30.0.1` | smart TV, IoT, ospiti WiFi | solo Internet |
| 40 — Downloads | `10.40.0.0/24` | `10.40.0.1` | qBittorrent + VPN egress | solo Internet via VPN (aggiunta in Fase 4) |

### Regole firewall inter-VLAN

```
VLAN 10 → qualsiasi          ALLOW   # admin
VLAN 20 → Internet           ALLOW
VLAN 20 → nebula :80/:443    ALLOW   # servizi web
VLAN 20 → nebula :22/:6443   DENY    # SSH e k3s solo VLAN 10
VLAN 20 → RFC1918            DENY
VLAN 30 → Internet           ALLOW
VLAN 30 → RFC1918            DENY
VLAN 40 → Internet via VPN   ALLOW
VLAN 40 → RFC1918            DENY
```

### Cosa cambia su nebula

- `enp1s0` diventa trunk 802.1Q (niente più IP diretto sull'interfaccia fisica)
- Subinterface `enp1s0.10` con IP statico `10.10.0.2/24`
- Gateway: `10.10.0.1` (hEX S VLAN 10)
- `networking.nix` aggiornato di conseguenza
- Record DNS `lab.paroparo.it` aggiornati a `10.10.0.2`

### Fritz!Box: abilitare PPPoE passthrough

1. `Internet → Dati di accesso` → abilita **Vista avanzata**
2. Account information → `No`
3. `Cambiare impostazioni connessione` → VLAN ID: `100`, Encapsulation: **Bridged**
4. Spunta **"I dispositivi collegati possono stabilire connessioni Internet proprie"**
5. Rimuovi spunta da "Verifica connessione dopo Applica" → Applica

### WireGuard ingress

Gira direttamente su hEX S (RouterOS v7 nativo). I peer remoti entrano in
VLAN 10 come se fossero fisicamente in LAN. Zero modifiche a nebula.
