{ pkgs,inputs,specialArgs,... }:
let
  inherit (specialArgs) username;
in
  {
    imports = [
      ../common.nix
    ];
}
