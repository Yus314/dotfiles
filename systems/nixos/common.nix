{ pkgs, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/default.yaml;
    age = {
      keyFile = "/home/kaki/.config/sops/age/keys.txt";
      generateKey = true;
    };
  };
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "kaki";
      };
    };
  };

}
