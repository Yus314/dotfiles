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
                autopep8 = {
                  enabled = true;
                };
              };
            };
          };
          rust-analyzer = {
            enable = true;
            installCargo = true;
            installRustc = true;
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
                "<M-c>" = "create";
              };
              "i" = {
                "<M-c>" = "create";
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
      rust-tools = {
        enable = true;
        inlayHints = {
          auto = true;
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

    colorschemes.nord = {
      enable = true;
    };
    extraConfigLua = ''
         local Terminal = require('toggleterm.terminal').Terminal

         local cargo_run = Terminal:new({
         	cmd = "cargo run",
                hidden = true, -- 通常のToggleTermコマンドでは開かれない
                direction = "float", -- floatingウィンドウで開く
                float_opts = {
                  border = "curved", -- ウィンドウの境界線の種類
      winblend = 30
                },
       close_on_exit = false,
              })

              function _cargo_run_toggle()
                cargo_run:toggle() -- ターミナルを開く/閉じる
              end

              vim.api.nvim_set_keymap("n", "<leader>r", "<cmd>lua _cargo_run_toggle()<CR>", {noremap = true, silent = true})
    '';
  };
}
