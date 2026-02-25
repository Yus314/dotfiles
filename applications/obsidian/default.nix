{ pkgs, ... }:
{
  programs.obsidian = {
    enable = true;
    package = pkgs.obsidian;
    vaults.main = {
      target = "dropbox/obsidian-vault";
    };
  };
}
