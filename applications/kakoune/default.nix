{ pkgs, ... }:
{
  home.packages = with pkgs; [
    kakoune-lsp
    nixd
  ];

  programs.kakoune = {
    enable = true;
    plugins = [
      pkgs.kakounePlugins.kakoune-scrollback
      pkgs.kakounePlugins.kakoune-autothemes
    ];
    colorSchemePackage = pkgs.kakounePlugins.kakoune-themes;
    extraConfig = ''
      hook global RegisterModified '"' %{
        nop %sh{
          printf %s "$kak_main_reg_dquote" | ${./osc52-copy.sh}
        }
      }

      set-option global autothemes_dark_theme modus-vivendi
      set-option global autothemes_light_theme modus-operandi
      autothemes-enable

      eval %sh{kak-lsp --kakoune -s $kak_session}
      lsp-enable

      hook global BufSetOption filetype=nix %{
          set-option buffer lsp_servers %{
              [nixd]
              root_globs = ["flake.nix", "shell.nix", ".git", ".hg"]
              [nixd.settings.nixd]
              formatting.command = ["nixfmt"]
              [nixd.settings.nixd.nixpkgs]
              expr = "import <nixpkgs> { }"
              [nixd.settings.nixd.options.nixos]
              expr = "(builtins.getFlake (\"git+file://\" + toString ./.)).nixosConfigurations.lawliet.options"
              [nixd.settings.nixd.options.home-manager]
              expr = "(builtins.getFlake (\"git+file://\" + toString ./.)).nixosConfigurations.lawliet.options.home-manager.users.type.getSubOptions []"
          }
      }

      map global user l ':enter-user-mode lsp<ret>' -docstring 'LSP mode'
    '';
    config = {
      keyMappings = [
        {
          mode = "normal";
          key = "d";
          effect = "h";
        }
        {
          mode = "normal";
          key = "s";
          effect = "j";
        }
        {
          mode = "normal";
          key = "t";
          effect = "k";
        }
        {
          mode = "normal";
          key = "n";
          effect = "l";
        }
        {
          mode = "normal";
          key = "h";
          effect = "s";
        }
        {
          mode = "normal";
          key = "l";
          effect = "d";
        }
        {
          mode = "normal";
          key = "<a-y>";
          effect = "<a-i>";
        }
        {
          mode = "normal";
          key = "<a-v>";
          effect = "<a-S>";
        }
        {
          mode = "normal";
          key = "D";
          effect = "H";
        }
        {
          mode = "normal";
          key = "S";
          effect = "J";
        }
        {
          mode = "normal";
          key = "T";
          effect = "K";
        }
        {
          mode = "normal";
          key = "N";
          effect = "L";
        }
        {
          mode = "normal";
          key = "L";
          effect = "N";
        }
        {
          mode = "normal";
          key = "H";
          effect = "S";
        }
      ];
    };
  };
}
