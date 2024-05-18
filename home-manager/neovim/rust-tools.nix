{
  programs.nixvim.plugins.rust-tools = {
    enable = true;
    #   inlayHints = {
    #     auto = true;
    #   };
    server = {
      check = {
        command = "clippy";
      };
      checkOnSave = true;
    };
  };
}
