vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# The default `gx` command, installed by the netrw plugin, doesn't open a link
# correctly when it's inside a man page.
# Ex:  :Man zsh  →  http://sourceforge.net/projects/zsh/

# So, I implement my own solution.

# Don't add  `<unique>`; it could  raise spurious errors  when we debug  and for
# some reason this plugin is sourced after netrw.
nnoremap <unique> gx <Cmd>call gx#open()<CR>
xnoremap <unique> gx <C-\><C-N><Cmd>call gx#open()<CR>

# Also, install a `gX` mapping opening the url under the cursor in `w3m` inside
# a tmux pane.
# Idea:
# We  could  use  `gx`  for  the  two mappings,  and  make  the  function  react
# differently depending on `v:count`.
nnoremap <unique> gX <Cmd>call gx#open(v:true)<CR>
xnoremap <unique> gX <C-\><C-N><Cmd>call gx#open(v:true)<CR>

