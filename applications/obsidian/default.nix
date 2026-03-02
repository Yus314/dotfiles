{ pkgs, lib, ... }:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  programs.obsidian = {
    enable = true;
    package = if isLinux then pkgs.obsidian else null;
    vaults.main = {
      target = "obsidian-vault";
      settings.communityPlugins = [
        { pkg = pkgs.obsidian-biblib; }
      ];
    };
  };

  xdg.desktopEntries = lib.mkIf isLinux {
    obsidian = {
      name = "Obsidian";
      comment = "Knowledge base";
      exec = "obsidian %u";
      icon = "obsidian";
      categories = [ "Office" ];
      mimeType = [ "x-scheme-handler/obsidian" ];
      startupNotify = true;
      settings = {
        StartupWMClass = "obsidian";
        Keywords = "notes;knowledge base;markdown;";
      };
    };
  };
}
