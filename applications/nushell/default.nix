{
  programs.nushell = {
    enable = true;
    configFile.source = ./config.nu;
    envFile.source = ./env.nu;
  };
  home.file.".config/nushell/git-completions.nu".text = builtins.readFile ./git-completions.nu;
}
