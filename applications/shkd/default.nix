{
  services.skhd = {
    enable = true;
    skhdConfig = builtins.readFile ./config.txt;
  };
}
