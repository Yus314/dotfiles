{ pkgs, ... }:
let
  ghostty-themes = pkgs.fetchFromGitHub {
    owner = "anhsirk0";
    repo = "ghostty-themes";
    rev = "f41cef8ebf79c79fa6485066a92d389a9e3fc186";
    hash = "sha256-/QE7ek+PezjwIm2JwPhm03oYoe7msadziWL80SGduGI=";
  };
in
{
  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;

    # Enable for whichever shell you plan to use!
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;

    settings = {
      theme = "light:modus-operandi,dark:modus-vivendi";
      font-family = "Bizin Gothic Discord NF";
      font-size = 16;
    };
  };

  # テーマファイルを配置
  xdg.configFile."ghostty/themes".source = "${ghostty-themes}/themes";
}
