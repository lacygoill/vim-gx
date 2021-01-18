vim9 noclear

if exists('loaded') | finish | endif
var loaded = true

# The default `gx` command, installed by the netrw plugin, doesn't open a link
# correctly when it's inside a man page.
# Ex:  :Man zsh  →  http://sourceforge.net/projects/zsh/

# So, I implement my own solution.

nno <unique> gx <cmd>call gx#open()<cr>
xno <unique> gx <c-\><c-n><cmd>call gx#open()<cr>

# Also, install a `gX` mapping opening the url under the cursor in `w3m` inside
# a tmux pane.
# Idea:
# We  could  use  `gx`  for  the  two mappings,  and  make  the  function  react
# differently depending on `v:count`.
nno <unique> gX <cmd>call gx#open(v:true)<cr>
xno <unique> gX <c-\><c-n><cmd>call gx#open(v:true)<cr>

