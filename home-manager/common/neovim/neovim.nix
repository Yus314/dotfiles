{ pkgs, unstable, ... }:
let

  plugins = import ./plugins.nix {
    inherit pkgs;
    inherit unstable;
  };

  configFile = file: {
    "nvim/${file}".source = pkgs.substituteAll ({ src = ./. + "${file}"; } // plugins);
  };
  configFiles = files: builtins.foldl' (x: y: x // y) { } (map configFile files);
in
{
  programs.neovim = {
    enable = true;
    package = unstable.legacyPackages.x86_64-linux.neovim-unwrapped;
    vimAlias = true;

    extraPackages = with pkgs; [
      lua-language-server
      rust-analyzer
      texlab
      ruff-lsp
      (unstable.legacyPackages.x86_64-linux.ruff)
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
    ];
  };

  xdg.configFile =
    {
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
                norg
                java
                (pkgs.tree-sitter-grammars.tree-sitter-norg-meta)
                (pkgs.tree-sitter-grammars.tree-sitter-nu)
                org
              ]
            )).dependencies;
        }
      }/parser";
    }
    // configFiles [
      "/init.lua"
      "/lua/color.lua"
      "/lua/keymaps.lua"
      "/lua/lsp.lua"
      "/lua/nvim-cmp.lua"
      "/lua/options.lua"
      "/lua/specif.lua"

      "/lua/plugins/barbar.lua"
      "/lua/plugins/cmp.lua"
      "/lua/plugins/comment.lua"
      "/lua/plugins/conform.lua"
      "/lua/plugins/copilot.lua"
      "/lua/plugins/dial.lua"
      "/lua/plugins/gitsign.lua"
      "/lua/plugins/hop.lua"
      "/lua/plugins/lspconfig.lua"
      "/lua/plugins/lualine.lua"
      "/lua/plugins/markdown-preview.lua"
      "/lua/plugins/neorg.lua"
      "/lua/plugins/noice.lua"
      # "/lua/plugins/nu.lua"
      "/lua/plugins/null-ls.lua"
      "/lua/plugins/oil.lua"
      "/lua/plugins/onedark.lua"
      "/lua/plugins/rust-tools.lua"
      "/lua/plugins/skkeleton.lua"
      "/lua/plugins/telescope.lua"
      "/lua/plugins/toggleterm.lua"
      "/lua/plugins/tree-sitter.lua"
      # "/lua/plugins/vim-markdown.lua"
      "/lua/plugins/vimtex.lua"
      "/lua/plugins/orgmode.lua"
      "/lua/plugins/render-markdown.lua"
      "/lua/plugins/telekasten.lua"
      "/lua/plugins/nvim-markdown.lua"
      "/lua/plugins/yamlmatter.lua"

    ];
}
