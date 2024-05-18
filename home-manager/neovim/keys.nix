{
  programs.nixvim = {
    keymaps = [
      {
        mode = "n";
        key = "<leader>f";
        action = "<cmd>Telescope file_browser<CR>";
      }
      {
        mode = "n";
        key = " ";
        action = "<Nop>";
      }
    ];
  };
}
