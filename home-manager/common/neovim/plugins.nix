{ pkgs }:
let
  normalizedPluginAttr = p: {
    "${builtins.replaceStrings
      [
        "-"
        "."
      ]
      [
        "_"
        "_"
      ]
      (pkgs.lib.toLower p.pname)
    }" = p;
  };
  plugins = p: builtins.foldl' (x: y: x // y) { } (map normalizedPluginAttr p);
in
with pkgs.vimPlugins;
plugins [
  barbar-nvim
  cmp-buffer
  cmp-nvim-lsp
  cmp-path
  conform-nvim
  copilot-vim
  denops-vim
  gitsigns-nvim
  lazy-nvim
  lualine-nvim
  luasnip
  markdown-preview-nvim
  noice-nvim
  nui-nvim
  null-ls-nvim
  nvim-cmp
  nvim-lspconfig
  nvim-treesitter.withAllGrammars
  nvim-ts-autotag
  nvim-web-devicons
  plenary-nvim
  rust-tools-nvim
  telescope-file-browser-nvim
  telescope-nvim
  toggleterm-nvim
  tokyonight-nvim
  vim-markdown
  vimtex
  nvim-nu
]
