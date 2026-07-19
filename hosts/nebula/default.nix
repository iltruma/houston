{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./disko.nix
    ./backup.nix
    ./impermanence.nix
    ./k3s.nix
    ./technitium.nix
    ./beszel-agent.nix
    ../../modules/common.nix
  ];

  system.stateVersion = "25.11"; # NON modificare dopo il primo install

  console.keyMap = "it";

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

  documentation.enable = false;

  # CLI tool per cluster k3s: navigazione interattiva di pod, log live, stato
  # risorse. Si lancia da SSH con `k9s`. Sostituisce `kubectl get` ripetuti.
  environment.systemPackages = [ pkgs.k9s ];
}
