# hosts/eos/default.nix
#
# Configurazione principale dell'host eos (Dell Optiplex 3050).
# Aggrega: disko, hardware, networking + moduli riusabili da ./modules.
#
# Per buildare:
#   nix build .#nixosConfigurations.eos.config.system.build.toplevel
#
# Per applicare:
#   nixos-rebuild switch --flake .#eos
# (oppure --target-host root@192.168.178.2 per buildare in remoto)

{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./disko.nix

    # Moduli riusabili del repo
    ../../modules
  ];

  # ── system.stateVersion: NON modificare dopo il primo install ────────────────
  system.stateVersion = "25.11";

  # ── console: keyboard italiano ───────────────────────────────────────────────
  console.keyMap = "it";

  # ── Nix settings ────────────────────────────────────────────────────────────
  nix = {
    settings = {
      auto-optimise-store = true;
      substituters = [ "https://cache.nixos.org/" ];
      trusted-users = [ "root" "cosimo" ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # ── Manciata di doc serve a zero se leggi i .md ────────────────────────────
  documentation.enable = false;
}
