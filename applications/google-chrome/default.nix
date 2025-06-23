{ pkgs, ... }:
{
  programs.google-chrome = {
    enable = true;
    #commandLineArgs = [
    #  "--enable-features=UseOzonePlatfor"

    #"--ozone-platform=x11"
    #];
  };
}
