{ config, pkgs, inputs, ... }:
let
in
{
  home=rec {
    username = "kaki";
    homeDirectory = "/home/${username}";
    stateVersion = "23.11";
    packages = with pkgs; [
      cowsay
      bat
      tldr
			nomacs
    ];
  };
  imports=[ inputs.nixvim.homeManagerModules.nixvim ];
  programs.nixvim = {
    enable = true;
    opts = {
      number = true;
      tabstop = 2;
      shiftwidth = 2;
      smartindent = true;
    };
    plugins = {
      lsp-format = {
        enable = true;
      };
      lsp = {
        enable = true;
        servers = {
          #nixd = {
          #  enable = true;
          #  settings = {
          #    formatting = {
          #      command = "nixpkgs-fmt";
          #    };
          #  };
          #};
          pylsp = {
            enable = true;
            settings = {
              plugins = {
                flake8 = {
                  enabled = true;
									ignore = ["E203" ];
                };
                isort = {
                  enabled = true;
                };
                black = {
                  enabled = true;
                };
              };
            };
          };
				};
        keymaps = {
          silent = false;
          diagnostic = {
            "[d" = "goto_next";
            "]d" = "goto_prev";
          };
          lspBuf = {
            "gd" = "declaration";
            "gD" = "definition";
            "K" = "hover";
            "gi" = "implementation";
            "<C-k>" = "signature_help";
            "<space>wa" = "add_workspace_folder";
            "<space>wr" = "remove_workspace_folder";
            "<space>wl" = "list_workspace_folders";
            "<space>D" = "type_definition";
            "<space>rn" = "rename";
            "<space>ca" = "code_action";
            "gr" = "references";
            "<space>f" = "format";
          };
        };
      };
      nvim-cmp = {
        enable = true;
        autoEnableSources = true;
        sources = [
          { name = "nvim_lsp"; }
          { name = "path"; }
        ];
      };
      telescope = {
        enable = true;
      };
      lualine = {
        enable = true;
      };
      copilot-vim = {
        enable = true;
      };



      # 追加するプラグイン
      # markdown-preview-nvim
      # vim-markdown

    };
    extraPlugins = [
      pkgs.vimPlugins.onenord-nvim
      pkgs.vimPlugins.fern-vim
    ];
    colorscheme = "onenord";
  };
  programs.zsh = {
    enable = true;
    autocd = true;
    history = {
      ignoreAllDups = true;
    };
    enableCompletion = true;
    syntaxHighlighting = {
      enable = true;
    };
    #autosuggestion = {
    #	enable = true;
    #};
    enableAutosuggestions = true;
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };
  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        dimensions = {
          lines = 30;
          columns = 100;
        };
      };
      font = {
        normal = {
          family = "Monospace";
          style = "Regular";
        };
        bold = {
          family = "Monospace";
          style = "Bold";
        };
        italic = {
          family = "Monospace";
          style = "Italic";
        };
        size = 12.0;
      };
      colors = {
        primary = {
          background = "#2e3340";
          foreground = "#d8dee9";
          dim_foreground = "#a5abb6";
        };
        cursor = {
          text = "#2e3440";
          cursor = "#d8dee9";
        };
        vi_mode_cursor = {
          text = "#2e3440";
          cursor = "#d8dee9";
        };
        selection = {
          text = "CellForeground";
          background = "#4c566a";
        };
        search = {
          matches = {
            foreground = "CellBackground";
            background = "#88c0d0";
          };
          #bar = {
          #  background =  "#434c5e";
          #  foreground = "#d8dee9";
          #};
        };
        normal = {
          black = "#3b4252";
          red = "#bf616a";
          green = "#a3be8c";
          yellow = "#ebcb8b";
          blue = "#81a1c1";
          magenta = "#b48ead";
          cyan = "#88c0d0";
          white = "#e5e9f0";
        };
        bright = {
          black = "#4c566a";
          red = "#bf616a";
          green = "#a3be8c";
          yellow = "#ebcb8b";
          blue = "#81a1c1";
          magenta = "#b48ead";
          cyan = "#8fbcbb";
          white = "#eceff4";
        };
        dim = {
          black = "#373e4d";
          red = "#94545d";
          green = "#809575";
          yellow = "#b29e75";
          blue = "#68809a";
          magenta = "#8c738c";
          cyan = "#6d96a5";
          white = "#aeb3bb";
        };
      };
    };
  };

  programs.vivaldi = {
    enable = true;
  };
  programs.git = {
    enable = true;
    userName = "Yus314";
    userEmail = "shizhaoyoujie@gmail.com";
  };
  programs.home-manager.enable = true;
}
