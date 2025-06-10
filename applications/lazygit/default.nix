{
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        showIcons = true;
      };
      keybinding = {
        universal = {
          prevItem-alt = "t";
          nextItem-alt = "h";
          scrollLeft = "D";
          scrollRight = "N";
          prevBlock-alt = "d";
          nextBlock-alt = "n";
          prevMatch = "B";
          remove = "e";
          new = "b";
        };
      };
    };
  };
}
