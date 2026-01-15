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
      # Nerd Font symbols mapping (v3.0+)
      symbol_map = "U+e000-U+e00a,U+ea60-U+ebeb,U+e0a0-U+e0c8,U+e0ca,U+e0cc-U+e0d7,U+e200-U+e2a9,U+e300-U+e3e3,U+e5fa-U+e6b1,U+e700-U+e7c5,U+ed00-U+efc1,U+f000-U+f2ff,U+f0001-U+f1af0,U+f300-U+f372,U+f400-U+f533,U+f500-U+fd46 Symbols Nerd Font Mono";
    };
    shellIntegration = {
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
    };
  };
}
