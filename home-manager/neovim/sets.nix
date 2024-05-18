{
  programs.nixvim = {
    enable = true;
    opts = {
      number = true;
      tabstop = 4;
      shiftwidth = 4;
      smartindent = true;
      termguicolors = true;
    };
    globals.mapleader = " ";
  };
}
