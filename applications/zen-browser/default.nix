{ inputs, pkgs, ... }:
{
  imports = [ inputs.zen-browser.homeModules.beta ];
  programs.zen-browser = {
    enable = true;
    profiles.kaki = {
      extensions = {
        packages = (
          with pkgs.firefox-addons;
          [
            bitwarden
            ublock-origin
            vimium
          ]
        );
      };
    };
  };
}
