{
  programs.nixvim.plugins.packer = {
    enable = true;
    plugins = [
      "wbthomason/packer.nvim"
      "epwalsh/obsidian.nvim"
      "folke/which-key.nvim"
    ];
  };
}
