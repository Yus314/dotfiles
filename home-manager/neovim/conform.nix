{
  programs.nixvim.plugins.conform-nvim = {
    enable = true;
    notifyOnError = true;
    formattersByFt = {
      nix = ["alejandra"];
      css = ["prettierd" "prettier"];
      rust = ["rustfmt"];
      python = ["isort" "black"];
    };
    formatOnSave = {
      lspFallback = true;
    };
  };
}
