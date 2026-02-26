{ pkgs, ... }:
{
  programs.obsidian = {
    enable = true;
    package = pkgs.obsidian;
    vaults.main = {
      target = "dropbox/obsidian-vault";
    };
  };

  xdg.desktopEntries.obsidian = {
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
}
