{ pkgs, ... }:
{
  programs.vivaldi = {
    enable = false;

    package = pkgs.vivaldi;
    commandLineArgs = [
      "--enable-features=UseOzonePlatfor"
      "--ozone-platform=x11"
    ];
  };
}
