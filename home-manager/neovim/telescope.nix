{
  programs.nixvim.plugins.telescope = {
    enable = true;
    enabledExtensions = [
      "file_browser"
    ];
    extensions = {
      file_browser = {
        enable = true;
      };
    };
  };
}
