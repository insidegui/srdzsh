source "$1"

[[ $HISTFILE == "$HOME/.zsh_history" ]] || {
	print -u2 "unexpected HISTFILE: $HISTFILE"
	exit 1
}
[[ $HISTSIZE == 10000 && $SAVEHIST == 10000 ]] || {
	print -u2 "history size defaults were not applied"
	exit 1
}
[[ "$(bindkey "${terminfo[kcuu1]}")" == *up-line-or-history* ]] || {
	print -u2 "Up-arrow key binding is not active"
	exit 1
}
(( $+functions[compdef] )) || {
	print -u2 "completion initialization failed"
	exit 1
}

print -s -- srd-history-smoke
fc -W "$HISTFILE"
grep -q srd-history-smoke "$HISTFILE" || {
	print -u2 "history file write failed"
	exit 1
}
