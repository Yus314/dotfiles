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
      (pkgs.lib.toLower p.pname)}" = p;
  };
  plugins = p: builtins.foldl' (x: y: x // y) { } (map normalizedPluginAttr p);
in
with pkgs.vimPlugins;
plugins [
lualine-nvim
barbar-nvim
toggleterm-nvim
tokyonight-nvim
lazy-nvim
noice-nvim
nvim-cmp
luasnip
cmp-nvim-lsp
cmp-path
cmp-buffer
copilot-vim
gitsigns-nvim
nui-nvim
telescope-nvim
plenary-nvim
telescope-file-browser-nvim
nvim-ts-autotag
markdown-preview-nvim
rust-tools-nvim
nvim-lspconfig
nvim-web-devicons
]

