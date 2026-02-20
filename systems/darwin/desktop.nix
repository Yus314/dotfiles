{
  self,
  pkgs,
  ...
}:
{
  security.pam.services.sudo_local.touchIdAuth = true;
  my.services.aquaskk = {
    enable = true;
    package = pkgs.aquaskk;
  };
  system.defaults.NSGlobalDomain.AppleInterfaceStyleSwitchesAutomatically = true;
}
