{
  self,
  pkgs,
  ...
}:
let
  aquaskk = pkgs.callPackage ../../pkgs/aquaskk { };
in
{
  security.pam.services.sudo_local.touchIdAuth = true;
  my.services.aquaskk.enable = true;
  my.services.aquaskk.package = aquaskk;
}
