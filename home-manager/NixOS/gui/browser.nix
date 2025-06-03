{ pkgs, ... }:
{
  programs.vivaldi = {
    enable = true;

    package = pkgs.vivaldi;
    commandLineArgs = [
      "--enable-features=UseOzonePlatfor"
      "--ozone-platform=x11"
    ];
  };
}
