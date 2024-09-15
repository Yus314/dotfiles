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
	menus : [
		{
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
				fd -t d
				| fzf --tac  
				| lines
				| each { |v|  { value: ($v | str trim) } } 
		
    }
}
	]
	keybindings: [
		    {
        name: complete_in_cd
        modifier: alt
        keycode: char_c
        mode: [emacs, vi_normal, vi_insert]
        event: [
            { edit: clear }
            { edit: insertString value: "./" }
            { send: Menu name: fzf_menu }
			{ send: Enter }
        ]
    }
	]
}
