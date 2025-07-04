{ pkgs, ... }:
let

  plugins = import ./plugins.nix {
    inherit pkgs;
  };

  configFile =
    file:
    let
      srcPath = ./. + "/${file}";
      replacements = plugins;
    in
    {
      "nvim/${file}".source = pkgs.replaceVars srcPath replacements;
    };

  configFiles = files: builtins.foldl' (x: y: x // y) { } (map configFile files);
in
{
  programs.neovim = {
    enable = false;
    vimAlias = true;

    extraPackages = with pkgs; [
      lua-language-server
      rust-analyzer
      texlab
      ruff
      python312Packages.python-lsp-ruff
      python312Packages.python-lsp-server
      rustfmt
      nil
      nixfmt-rfc-style
      nodejs
      tree-sitter
      deno
      luajitPackages.jsregexp
      lua54Packages.jsregexp
      luajitPackages.luarocks
      luajit_openresty
      gnumake
      luajitPackages.lua-utils-nvim
      luajitPackages.compat53
      libgccjit
      jdt-language-server
      python312 # for zotcite
      python312Packages.pyyaml # for zotcite
      python312Packages.pynvim # for zotcite
      python312Packages.pyqt5 # for zotcite
      python312Packages.poppler-qt5 # for zotcite
    ];
  };

  xdg.configFile = {
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
              python
              latex
              nix
              java
              (pkgs.tree-sitter-grammars.tree-sitter-norg-meta)
              (pkgs.tree-sitter-grammars.tree-sitter-nu)
            ]
          )).dependencies;
      }
    }/parser";
  };
  # // configFiles [
  #   "init.lua"
  #   #"lua/color.lua"
  #   "lua/keymaps.lua"
  #   "lua/lsp.lua"
  #   "lua/nvim-cmp.lua"
  #   "lua/options.lua"
  #   "lua/specif.lua"

  #"lua/plugins/barbar.lua"
  #"lua/plugins/cmp.lua"
  #"lua/plugins/comment.lua"
  #   "lua/plugins/conform.lua"
  #   "lua/plugins/copilot.lua"
  #   "lua/plugins/dial.lua"
  #   "lua/plugins/gitsign.lua"
  #   "lua/plugins/hop.lua"
  #   "lua/plugins/lspconfig.lua"
  #   "lua/plugins/lualine.lua"
  #   "lua/plugins/markdown-preview.lua"
  #   "lua/plugins/noice.lua"
  # "/lua/plugins/nu.lua"
  #   "lua/plugins/null-ls.lua"
  #   "lua/plugins/oil.lua"
  #   "lua/plugins/onedark.lua"
  #   "lua/plugins/rust-tools.lua"
  #   "lua/plugins/skkeleton.lua"
  #   "lua/plugins/telescope.lua"
  #   "lua/plugins/toggleterm.lua"
  #   "lua/plugins/tree-sitter.lua"
  # "/lua/plugins/vim-markdown.lua"
  #   "lua/plugins/vimtex.lua"
  #   "lua/plugins/orgmode.lua"
  #   "lua/plugins/render-markdown.lua"
  #   "lua/plugins/telekasten.lua"
  #   "lua/plugins/nvim-markdown.lua"
  #   "lua/plugins/yamlmatter.lua"
  #   "lua/plugins/zotcite.lua"

  # ];
}
