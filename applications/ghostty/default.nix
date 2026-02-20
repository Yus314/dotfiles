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

      # macOS Option as Alt (kittyのmacos_option_as_altに対応)
      macos-option-as-alt = "left";

      # macOSタブバー (kittyのtab_bar_edgeに対応)
      macos-titlebar-style = "tabs";

      # 新規タブで現在のディレクトリを引き継ぐ
      window-inherit-working-directory = true;

      # Nerd Fontシンボルマッピング (kittyのsymbol_mapに対応)
      font-codepoint-map = "U+E000-U+E00A,U+EA60-U+EBEB,U+E0A0-U+E0C8,U+E0CA,U+E0CC-U+E0D7,U+E200-U+E2A9,U+E300-U+E3E3,U+E5FA-U+E6B1,U+E700-U+E7C5,U+ED00-U+EFC1,U+F000-U+F2FF,U+F0001-U+F1AF0,U+F300-U+F372,U+F400-U+F533,U+F500-U+FD46=Symbols Nerd Font Mono";

      # キーバインド (kittyのkitty_modキーバインドに対応)
      keybind = [
        "ctrl+shift+d=previous_tab"
        "ctrl+shift+n=next_tab"
        "ctrl+shift+t=jump_to_prompt:-1"
        "ctrl+shift+s=jump_to_prompt:1"
        "ctrl+shift+enter=new_tab"
        "ctrl+shift+h=new_tab"
        "ctrl+shift+w=close_surface"
        "ctrl+shift+z=scroll_page_up"
        "ctrl+shift+v=scroll_page_down"
      ];
    };
  };

  # テーマファイルを配置
  xdg.configFile."ghostty/themes".source = "${ghostty-themes}/themes";
}
