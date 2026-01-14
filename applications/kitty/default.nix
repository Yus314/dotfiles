{
  programs.kitty = {
    enable = true;
    font = {
      name = "Bizin Gothic Discord NF";
      size = 18;
    };
    themeFile = "Modus_Vivendi";
    settings = {
      macos_option_as_alt = "left";
      allow_remote_control = "socket-only";
      listen_on = "unix:/tmp/kitty";
    };
    shellIntegration = {
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
    };
  };
}
