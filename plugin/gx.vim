if exists('g:loaded_gx')
    finish
endif
let g:loaded_gx = 1

" The default `gx` command, installed by the netrw plugin, doesn't open a link
" correctly when it's inside a man page.
" Ex:  :Man zsh  →  http://sourceforge.net/projects/zsh/

" So, I implement my own solution.

nno <silent><unique> gx :<c-u>call gx#open(0)<cr>
xno <silent><unique> gx :<c-u>call gx#open(0, 'vis')<cr>

" Also, install a `gX` mapping opening the url under the cursor in `w3m` inside
" a tmux pane.
" Idea:
" We  could  use  `gx`  for  the  two mappings,  and  make  the  function  react
" differently depending on `v:count`.
nno <silent><unique> gX :<c-u>call gx#open(1)<cr>
xno <silent><unique> gX :<c-u>call gx#open(1, 'vis')<cr>

