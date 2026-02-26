{ pkgs, config, ... }:
{
  home.packages = [ pkgs.sprout ];

  xdg.configFile."sprout/config.toml".text = ''
    vault_path = "/home/kaki/dropbox/obsidian-vault"
    exclude_dirs = [".git", ".obsidian", ".trash", ".claude", "attachments"]
  '';
}
