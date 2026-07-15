# hosts/taiga/default.nix
#
# Configurazione principale di Taiga — Raspberry Pi 4, stampante 3D.
#
# Stack: NixOS aarch64 + Klipper + Moonraker + Mainsail
#
# Per applicare da workstation:
#   nixos-rebuild switch --flake .#taiga \
#     --target-host pi@192.168.178.43 \
#     --build-host localhost
#
# Prerequisito (una volta sola sulla workstation):
#   boot.binfmt.emulatedSystems = [ "aarch64-linux" ];  # in eos config
#
# ── da fare al primo install ────────────────────────────────────────────────
#   1. Flash SD card con immagine NixOS aarch64 per Pi 4
#      (nix build .#nixosConfigurations.installer-taiga.config.system.build.isoImage)
#   2. Boot → SSH disponibile → nixos-rebuild switch --flake .#taiga
#   3. Copiare printer.cfg esistente in /var/lib/klipper/printer.cfg
#      (mutableConfig = true: klipper lo usa direttamente, non sovrascrive)

{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./networking.nix
    # moduli riusabili: common.nix (SSH, sops, utenti), impermanence, backup
    ../../modules/common.nix
    ../../modules/impermanence.nix
    # stack stampante
    ../../modules/klipper.nix
  ];

  system.stateVersion = "25.11";
}
