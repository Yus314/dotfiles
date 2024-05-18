{
  programs.nixvim.plugins.barbar = {
    enable = true;
    keymaps = {
      silent = true;
      previous = "[b";
      next = "]b";
      close = "<C-w>w";
    };
  };
}
