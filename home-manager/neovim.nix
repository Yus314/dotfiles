{pkgs, ...}: {
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
    plugins = {
      lsp-format = {enable = true;};
      lsp = {
        enable = true;
        servers = {
          nil_ls = {
            enable = true;
          };
          nixd = {
            enable = false;
          };
          html = {
            enable = true;
          };
          cssls = {
            enable = true;
          };
          pylsp = {
            enable = true;
            settings = {
              plugins = {
                flake8 = {
                  enabled = true;
                  maxLineLength = 119;
                  ignore = ["E203"];
                };
                black = {
                  enabled = true;
                  line_length = 119;
                };
                isort = {
                  enabled = true;
                };
              };
            };
          };
          rust-analyzer = {
            enable = true;
            installCargo = true;
            installRustc = true;
            settings = {
              checkOnSave = true;
              check = {
                command = "clippy";
              };
              inlayHints = {
                chainingHints.enable = true;
                parameterHints.enable = true;
                typeHints.enable = true;
              };
            };
          };
        };
        keymaps = {
          silent = true;
          lspBuf = {
            gd = {
              action = "definition";
              desc = "Goto Definition";
            };
            gr = {
              action = "references";
              desc = "Goto References";
            };
            gD = {
              action = "declaration";
              desc = "Goto Declaration";
            };
            gI = {
              action = "implementation";
              desc = "Goto Implementation";
            };
            gT = {
              action = "type_definition";
              desc = "Type Definition";
            };
            K = {
              action = "hover";
              desc = "Hover";
            };
            "<leader>cw" = {
              action = "workspace_symbol";
              desc = "Workspace Symbol";
            };
            "<leader>cr" = {
              action = "rename";
              desc = "Rename";
            };
          };
        };
      };
      nvim-cmp = {
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
      luasnip = {
        enable = true;
      };
      noice = {
        enable = true;
      };
      barbar = {
        enable = true;
        keymaps = {
          silent = true;
          previous = "[b";
          next = "]b";
          close = "<C-w>w";
        };
      };
      telescope = {
        enable = true;
        enabledExtensions = [
          "file_browser"
        ];
        extensions = {
          file_browser = {
            enable = true;
            mappings = {
              "n" = {
                "<A-x>" = "remove";
              };
              "i" = {
                "<A-x>" = "remove";
              };
            };
          };
        };
      };
      lualine = {
        enable = true;
      };
      toggleterm = {
        enable = true;
        direction = "float";
        floatOpts = {
          border = "curved";
          winblend = 10;
        };
      };
      copilot-vim = {
        enable = true;
      };
      treesitter = {
        enable = true;
        indent = true;
      };
      ts-autotag = {
        enable = true;
      };
      gitsigns = {
        enable = true;
      };
      rust-tools = {
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
      none-ls = {
        enable = true;
        enableLspFormat = true;
      };
      conform-nvim = {
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

      # 追加するプラグイン
      # markdown-preview-nvim
      # vim-markdown
    };
    extraPlugins = with pkgs.vimPlugins; [
    ];

    colorschemes.tokyonight = {
      enable = true;
    };
    extraConfigLua = ''
                   local Terminal = require('toggleterm.terminal').Terminal

                   local cargo_run = Terminal:new({
        cmd = "cargo run",
        hiddcen = true, -- 通常のToggleTermコマンドでは開かれない
        close_on_exit = false,
        })

       function _cargo_run_toggle()
       cargo_run:toggle() -- ターミナルを開く/閉じる
       end

       vim.api.nvim_set_keymap("n", "<leader>r", "<cmd>lua _cargo_run_toggle()<CR>", {noremap = true, silent = true})


      local cargo_test = Terminal:new({
        cmd = "cargo compete t " .. vim.fn.expand("%:t:r"),
        hidden = true, -- 通常のToggleTermコマンドでは開かれない
        close_on_exit = false,
        })

       function _cargo_test_toggle()
       cargo_test:toggle() -- ターミナルを開く/閉じる
       end

       vim.api.nvim_set_keymap("n", "<leader>t", "<cmd>lua _cargo_test_toggle()<CR>", {noremap = true, silent = true})

      local cargo_submit = Terminal:new({
        cmd = "cargo compete submit " .. vim.fn.expand("%:t:r"),
        hidden = true, -- 通常のToggleTermコマンドでは開かれない
        close_on_exit = false,
        })

       function _cargo_submit_toggle()
       cargo_submit:toggle() -- ターミナルを開く/閉じる
       end

       vim.api.nvim_set_keymap("n", "<leader>s", "<cmd>lua _cargo_submit_toggle()<CR>", {noremap = true, silent = true})

       local lazygit = Terminal:new({
        cmd = "lazygit",
        hidden = true, -- 通常のToggleTermコマンドでは開かれない
        })

       function _lazygit_toggle()
       lazygit:toggle()
       end

       vim.api.nvim_set_keymap("n", "<leader>g", "<cmd>lua _lazygit_toggle()<CR>", {noremap = true, silent = true})
    '';
  };
}
