alias c = cargo
#source /home/kaki/.config/nushell/git-completions.nu
source /home/kaki/.cache/carapace/init.nu
let fish_completer = {|spans|
	fish --command $'complete "--do-complete=($spans | str join " ")"'
	| $"value(char tab)description(char newline)" + $in
	| from tsv --flexible --no-infer
}
 let carapace_completer = {|spans|
     carapace $spans.0 nushell ...$spans | from json
} 
let external_completer = {|spans|
	match $spans.0 {
		_ => fish_completer
 	} | do $in $spans
}
$env.config = {
	show_banner: false
	completions: { 
		algorithm: "fuzzy"
		external: {
			enable: true
			completer: $fish_completer
		}
	}
	edit_mode: "vi"
	keybindings: [
		{
			name: change_dir_with_fzf
			modifier: alt
			keycode: char_c
			mode: vi_insert
			event: {
				send: executehostcommand
				cmd: "cd (ls | where type == dir | each { | row | $row.name} | str join (char nl) | fzf | decode utf-8 | str trim)"
			}
		}
	]
}
