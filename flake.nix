# Astra — flake NixOS
#
# Entry point per la configurazione NixOS di eos.
# `nixosConfigurations.eos` è il sistema principale (server Dell Optiplex 3050).
#
# Per buildare senza applicare:
#   nix build .#nixosConfigurations.eos.config.system.build.toplevel
#
# Per applicare da remoto (da workstation):
#   nixos-rebuild switch --flake .#eos --target-host root@192.168.178.2 --build-host localhost
#
# Per installare/reinstallare via SSH (richiede Linux già avviato sul target, es. Debian live):
#   nix run github:nix-community/nixos-anywhere -- --flake .#eos root@192.168.178.2
#
# Pinning:
#   - nixpkgs:        nixos-25.11 (stable)
#   - sops-nix:       ultima stable, convergenza con Flux SOPS esistente
#   - disko:          partizionamento ZFS dichiarativo
#   - nixos-anywhere: pinnato per riproducibilità; si invoca direttamente con nix run github:

{
  description = "Astra — NixOS homelab su Dell Optiplex 3050";

  inputs = {
    # Pin nixpkgs al canale stable 25.11
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # sops-nix: secrets host cifrati con SOPS + age (stessa chiave di Flux)
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # disko: partizionamento ZFS dichiarativo
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixos-anywhere: installa NixOS su qualsiasi Linux via SSH (usa kexec + disko)
    # Uso: nix run .#nixos-anywhere -- --flake .#eos root@192.168.178.2
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };

    # impermanence: bind mount dichiarativi da /persist verso il root effimero
    impermanence.url = "github:nix-community/impermanence";

    # nixos-hardware: moduli hardware per device specifici (Raspberry Pi 4)
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, sops-nix, disko, nixos-anywhere, impermanence, nixos-hardware, ... }: {
    nixosConfigurations.eos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        # Modulo host (aggrega hardware, networking, disko e tutti i moduli riusabili)
        ./hosts/eos
        # Moduli esterni (input del flake)
        sops-nix.nixosModules.sops
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
      ];
    };

    # Taiga — Raspberry Pi 4, stampante 3D (Klipper + Moonraker + Mainsail)
    # Build da workstation: nixos-rebuild switch --flake .#taiga \
    #   --target-host pi@192.168.178.43 --build-host localhost
    nixosConfigurations.taiga = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./hosts/taiga
        nixos-hardware.nixosModules.raspberry-pi-4
        sops-nix.nixosModules.sops
        impermanence.nixosModules.impermanence
      ];
    };

    # ISO installer headless: SSH + chiave pubblica + IP statico 192.168.178.2
    # Build: nix build .#nixosConfigurations.installer.config.system.build.isoImage
    nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./hosts/installer ];
    };
  };
}
