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
let fzf_menu =  {
    name: fzf_menu
    only_buffer_difference: true
    marker: "# "
    type: {
        layout: columnar
        columns: 1
        col_width: 20
        col_padding: 2
    }
    style: {
        text: green
        selected_text: green_reverse
        description_text: yellow
    }
    source: { |buffer, position|
        fzf --no-sort --tac  
        | lines
        | each { |v|  { value: ($v | str trim) } }
    }
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
			    {
      name: fuzzy_history
      modifier: alt
      keycode: char_c
      mode: emacs
      event: {
        send: executehostcommand
        cmd: "commandline (history | each { |it| $it.command } | uniq | reverse | str collect (char nl) | fzf --layout=reverse --height=40% -q (commandline) | decode utf-8 | str trim)"
      }
    }
		}
	]
}
