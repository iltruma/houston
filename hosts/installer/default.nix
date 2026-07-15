# hosts/installer/default.nix
#
# ISO NixOS minimale per installazione headless di Eos.
#
# Cosa fa:
#   - Parte dal modulo NixOS built-in installation-cd-minimal
#   - Abilita SSH con la chiave pubblica di cosimo (da modules/keys.nix)
#   - Configura IP statico 192.168.178.2/24 su enp1s0 al boot
#     (niente DHCP: Eos ha IP fisso, vogliamo SSH subito e senza sorprese)
#
# Come buildare (dalla workstation):
#   nix build .#nixosConfigurations.installer.config.system.build.isoImage
#   # ISO in: result/iso/nixos-*.iso
#
# Come scrivere su USB:
#   sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
#
# Dopo il boot su Eos:
#   ssh root@192.168.178.2
#   nix run github:nix-community/nixos-anywhere -- --flake .#eos root@192.168.178.2

{ modulesPath, lib, ... }:

{
  imports = [
    # Modulo NixOS built-in: produce una ISO bootable minimale
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # ── SSH: abilitato con chiave pubblica, nessuna password ─────────────────────
  # mkForce necessario: installation-cd-minimal non avvia sshd di default,
  # oppure lo avvia solo su richiesta. Forziamo multi-user.target.
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  users.users.root.openssh.authorizedKeys.keys = import ../../modules/keys.nix;

  # ── Rete: IP statico su enp1s0 ───────────────────────────────────────────────
  # Niente NetworkManager/DHCP: vogliamo IP prevedibile al boot.
  # enp1s0 è l'interfaccia ethernet di Eos (Dell Optiplex 3050, confermata).
  networking.useDHCP = false;
  networking.interfaces.enp1s0.ipv4.addresses = [
    {
      address = "192.168.178.2";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "192.168.178.1";
  networking.nameservers = [ "1.1.1.1" ];

  # ── Pacchetti minimi per nixos-anywhere ──────────────────────────────────────
  # nixos-anywhere richiede: tar, kexec-tools (già inclusi nel cd-minimal)
  # git e curl utili per debug manuale se serve.
}
