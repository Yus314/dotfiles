{
  programs.nixvim.extraConfigLua = ''
    require("obsidian").setup({
      workspaces = {
        {
          name = "obsidian",
          path = "~/obsidian",
        },
      },
      -- その他のオプションはここに追加
    })
  '';
}
