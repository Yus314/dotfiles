{
  programs.nixvim.plugins = {
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
  };
}
