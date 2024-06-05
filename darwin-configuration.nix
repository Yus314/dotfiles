{ pkgs, ... }: {
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = [ pkgs.vim ];

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;
  nixpkgs.hostPlatform = "aarch64-darwin";

  imports = [ ./home-manager/macOS/yabai.nix ./home-manager/macOS/shkd.nix ];

  #fonts.font = with pkgs; [
  #  noto-fonts-cjk-serif
  #  noto-fonts-cjk-sans
  #  noto-fonts-emoji
  #   nerdfonts
  # #  ];
  users = {
    users = {
      kakinumayuusuke = {
        shell = pkgs.zsh;
        description = "Devin Singh";
        home = "/Users/kakinumayuusuke";
      };
    };
  };
}
