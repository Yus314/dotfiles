{
  programs.nixvim.plugins.nvim-cmp = {
    enable = true;
    snippet = {
      expand = "luasnip";
    };
    sources = [
      {name = "nvim_lsp";}
      {
        name = "luasnip";
      }
    ];
    mapping = {
      "<C-r>>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
      "<C-j>" = "cmp.mapping.select_next_item()";
      "<C-k>" = "cmp.mapping.select_prev_item()";
      "<C-e>" = "cmp.mapping.abort()";
      "<C-b>" = "cmp.mapping.scroll_docs(-4)";
      "<C-f>" = "cmp.mapping.scroll_docs(4)";
      "<C-d>" = "cmp.mapping.complete()";
      "<CR>" = "cmp.mapping.confirm({ select = true })";
      "<S-CR>" = "cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true })";
    };
  };
}
