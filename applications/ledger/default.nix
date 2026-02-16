{ pkgs, ... }:
{
  programs.ledger = {
    enable = false;
    package = pkgs.ledger.override { gpgmeSupport = true; };
  };
  home.packages = with pkgs; [
    hledger
    hledger-web
    hledger-lots
  ];
}
