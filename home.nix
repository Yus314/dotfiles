{config, pkgs, inputs, ... }:
let 
in
{
	home = rec {
		username="kaki";
		homeDirectory = "/home/${username}";
		stateVersion = "23.11";
		packages = with pkgs; [
			pkgs.cowsay
			pkgs.bat
			pkgs.eza
			pkgs.tldr
		];
	};
	imports = [ inputs.nixvim.homeManagerModules.nixvim ];
	programs.nixvim = {
		enable = true;
		plugins = {
		};
	};
	programs.zsh = {
		enable = true;
		autocd = true;
		history = {
			ignoreAllDups = true;
		};
		enableCompletion = true;
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
				demensions = {
					lines = 30;
					columns = 100;
				};
			};
			font = {
				nomal = {
					family = "Monospace";
					style = "Regular";
				};
				bold = {
					family = "Monospace";
					style = "Bold";
				};	
				italic = {
					family = "monospace";
					style = "Italic";
				};
				size = 12.0;
			};	
			color = {
			primary = {
				backgroud = "0x282c34";
				foreground = "0xabb2bf";
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
		userEmail =  "shizhaoyoujie@gmail.com";
	};
	programs.home-manager.enable = true;
}
