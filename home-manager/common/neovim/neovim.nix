{ pkgs, ... }:
let

  plugins = import ./plugins.nix { inherit pkgs; };

  configFile = file: pkgs.substituteAll ({ src = file; } // plugins);

  configFiles = files: builtins.foldl' (x: y: x // y) { } (map configFile files);

  initLua = pkgs.substituteAll ({ src = ./init.lua; } // plugins);

  pluginsLua = pkgs.substituteAll ({ src = ./lua/plugins/plugins.lua; } // plugins);

  gitsign = pkgs.substituteAll ({ src = ./lua/plugins/gitsign.lua; } // plugins);

  markdown-preview = pkgs.substituteAll ({ src = ./lua/plugins/markdown-preview.lua; } // plugins);
in
{
  programs.neovim = {
    enable = true;
    vimAlias = true;

    extraPackages = with pkgs; [
      lua-language-server
      rust-analyzer
      texlab
	  ruff-lsp
      rustfmt
      nil
      nixfmt-rfc-style
      nodejs
      tree-sitter
      deno
      luajitPackages.jsregexp
      lua54Packages.jsregexp
    ];
  };

  # xdg.configFile =
  # configFiles [
  #   ./init.lua
  #   ./lua/plugins/plugins.lua
  #   ./lua/plugins/gitsign.lua
  #   ./lua/plugins/markdown-preview.lua
  #   ./lua/plugins/func.lua
  #   ./lua/options.lua
  #   ./lua/keymaps.lua
  #   ./lua/nvim-cmp.lua
  # ./lua/lsp.lua
  #   ./lua/color.lua
  #   ./SKK-JISYO.L
  # ]
  #   configFiles[./init.lua]
  #  // 
  # {
  #  "nvim/parser".source = "${
  #   pkgs.symlinkJoin {
  #    name = "treesitter-parsers";
  #   paths =
  #    (pkgs.vimPlugins.nvim-treesitter.withPlugins (
  #     plugins: with plugins; [
  #      c
  #     lua
  #    rust
  #   query
  #  vimdoc
  #     ]
  #   )).dependencies;
  #       }
  #    }/parser";
  # };
  xdg.configFile = {
    "nvim/init.lua".source = initLua;
    "nvim/lua/plugins/plugins.lua".source = pluginsLua;
    "nvim/lua/plugins/gitsign.lua".source = gitsign;
    "nvim/lua/plugins/markdown-preview.lua".source = markdown-preview;
    "nvim/lua/plugins/func.lua".source = ./lua/plugins/func.lua;
    "nvim/lua/options.lua".source = ./lua/options.lua;
    "nvim/lua/keymaps.lua".source = ./lua/keymaps.lua;
    "nvim/lua/nvim-cmp.lua".source = ./lua/nvim-cmp.lua;
    "nvim/lua/lsp.lua".source = ./lua/lsp.lua;
    "nvim/lua/specif.lua".source = ./lua/specif.lua;
    "nvim/lua/color.lua".source = ./lua/color.lua;
    "~/.skk/SKK-JISYO.L".source = ./SKK-JISYO.L;
    "nvim/parser".source = "${
      pkgs.symlinkJoin {
        name = "treesitter-parsers";
        paths =
          (pkgs.vimPlugins.nvim-treesitter.withPlugins (
            plugins: with plugins; [
              c
              lua
              rust
              query
              vimdoc
              markdown
              markdown-inline
              vim
              bash
              regex
            ]
          )).dependencies;
      }
    }/parser";
  };
}
