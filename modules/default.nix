# modules/default.nix
#
# Aggregatore di tutti i moduli NixOS riusabili del repo.
# Importato da hosts/eos/default.nix.
#
# Convenzione: un modulo per servizio/concern, in file separato.
# Aggiungere un nuovo servizio:
#   1. Crea modules/<servizio>.nix
#   2. Aggiungi l'import qui sotto
#   3. Abilita il servizio in hosts/eos/default.nix con services.<name>.enable = true
#      (oppure direttamente in modules/<servizio>.nix con un default true)

{ ... }:

{
  imports = [
    ./common.nix
    ./technitium.nix
    ./k3s.nix
    ./backup.nix
    ./impermanence.nix
  ];
}
