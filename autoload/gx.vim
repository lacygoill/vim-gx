if exists('g:autoloaded_gx')
    finish
endif
let g:autoloaded_gx = 1

let s:DIR = getenv('XDG_RUNTIME_VIM') == v:null ? '/tmp' : $XDG_RUNTIME_VIM

" Interface {{{1
fu gx#open(in_term, ...) abort "{{{2
    if a:0
        let z_save = [getreg('z'), getregtype('z')]
        norm! gv"zy
        let url = @z
        call setreg('z', z_save[0], z_save[1])
    else
        let url = s:get_url()
    endif

    if empty(url)
        return
    endif

    " [some book](~/Dropbox/ebooks/Later/Algo To Live By.pdf)
    if match(url, '^\%(https\=\|ftps\=\|www\)://') == -1
        " Don't use `expand()`!{{{
        "
        " We don't want something like `#anchor` to be replaced with the path to
        " the alternate file.
        "
        " We could also do sth like:
        "
        "     let url = expand(fnameescape(url))
        "
        " Not sure whether it's totally equivalent though...
        "}}}
        let url = substitute(url, '^\~', $HOME, '')
        if !filereadable(url)
            return
        endif
        let ext = fnamemodify(url, ':e')
        let cmd = get({'pdf': 'zathura'}, ext, 'xdg-open')
        let cmd = cmd..' '..shellescape(url)..' &'
        sil call system(cmd)
    else
        if a:in_term
            " Could we pass the shell command to `$ tmux split-window` directly?{{{
            "
            " Yes but the pane would be closed immediately.
            " Because by default, tmux closes  a window/pane whose shell command
            " has completed:
            "
            " > When the shell command completes, the window closes.
            " > See the remain-on-exit option to change this behaviour.
            "
            " For more info, see `man tmux`, and search:
            "
            "     new-window
            "     split-window
            "     respawn-pane
            "     set-remain-on-exit
            "}}}
            sil call system('tmux split-window -c '..s:DIR)
            " maximize the pane
            sil call system('tmux resize-pane -Z')
            " start `w3m`
            sil call system('tmux send-keys web \ '..shellescape(url)..' Enter')
            "                                    │{{{
            "                                    └ without the backslash,
            "
            " `tmux` would think  it's a space to separate the  arguments of the
            " `send-keys` command; therefore, it would remove it and type:
            "
            "             weburl
            "
            " instead of:
            "
            "             web url
            "
            " The backslash is there to tell it's a semantic space.
            "}}}
        else
            sil call system('xdg-open '..shellescape(url))
        endif
    endif
endfu
" }}}1
" Core {{{1
fu s:get_url() abort "{{{2
    " https://github.com/junegunn/vim-plug/wiki/extra
    if &filetype is# 'vim-plug'
        return s:get_url_vim_plug()
    endif

    let line = getline('.')
    let pos = getcurpos()
    " [text](link)
    let pat = '!\=\[.\{-}\]'
    let pat ..= '\%((.\{-})\|\[.\{-}\]\)'
    let g = 0
    norm! 1|
    let flags = 'cW'
    while search(pat, flags, line('.')) && g < 100
        let col_start_link = col('.')
        norm! %l
        let col_start_url = col('.')
        norm! %
        let col_end_url = col('.')
        if pos[2] >= col_start_link && pos[2] <= col_end_url
            let url = matchstr(line, '\%'..(col_start_url+1)..'c.*\%'..col_end_url..'c')
            break
        endif
        let g += 1
        let flags = 'W'
    endwhile
    call setpos('.', pos)

    if exists('url')
        let arg = {
            \ 'line': line,
            \ 'url': url,
            \ 'col_start_link': col_start_link,
            \ 'col_start_url': col_start_url,
            \ 'col_end_url': col_end_url,
            \ }
        return s:get_url_markdown_style(arg)
    else
        return s:get_url_regular()
    endif
endfu

fu s:get_url_markdown_style(arg) abort "{{{2
    let line = a:arg.line
    let url = a:arg.url
    let col_start_link = a:arg.col_start_link
    let col_start_url = a:arg.col_start_url
    let col_end_url = a:arg.col_end_url
    " [text](link)
    if matchstr(line, '\%'..col_start_url..'c.') is# '('
        " This is [an example](http://example.com/ "Title") inline link.
        let url = substitute(url, '\s*".\{-}"\s*$', '', '')

    " [text][ref]
    else
        " Visit [Daring Fireball][] for more information.
        " [Daring Fireball]: http://daringfireball.net/
        if url is# ''
            let ref = matchstr(line, '\%'..(col_start_link+1)..'c.*\%'..(col_start_url-1)..'c')
        else
            let ref = url
        endif
        if &filetype is# 'markdown'
            let cml = ''
        else
            let cml = '\V'..matchstr(get(split(&l:cms, '%s'), 0, ''), '\S*')..'\m'
        endif
        let url = filter(getline('.', '$'),
            \ {_,v -> v =~# '^\s*'..cml..'\s*\c\V['..ref..']:'})
        let url = matchstr(get(url, 0, ''), '\[.\{-}\]:\s*\zs.*')
        " [foo]: http://example.com/  "Optional Title Here"
        " [foo]: http://example.com/  'Optional Title Here'
        " [foo]: http://example.com/  (Optional Title Here)
        let pat = '\s\+\(["'']\).\{-}\1\s*$'
        let pat ..= '\|\s\+(.\{-})\s*$'
        let url = substitute(url, pat, '', '')
        " [id]: <http://example.com/>  "Optional Title Here"
        let url = trim(url, '<>')
    endif
    return url
endfu

fu s:get_url_regular() abort "{{{2
    let url = expand('<cWORD>')
    let pat = '\%(https\=\|ftps\=\|www\)://'
    if url !~# pat
        return ''
    endif

    " Which characters make a URL invalid?
    " https://stackoverflow.com/a/13500078

    " remove everything before the first `http`, `ftp` or `www`
    let url = substitute(url, '.\{-}\ze'..pat, '', '')

    " remove everything after the first `⟩`, `>`, `)`, `]`, `}`, backtick
    " but some wikipedia links contain parentheses:{{{
    "
    "         https://en.wikipedia.org/wiki/Daemon_(computing)
    "
    " In those cases,  we need to make an exception,  and not remove the
    " text after the closing parenthesis.
    "}}}
    let chars = match(url, '(') == -1 ? '[]⟩>)}`]' : '[]⟩>}`]'
    let url = substitute(url, '\v.{-}\zs'..chars..'.*', '', '')

    " remove everything after the last `"`
    let url = substitute(url, '\v".*', '', '')
    return url
endfu

fu s:get_url_vim_plug() abort "{{{2
    let line = getline('.')
    let sha  = matchstr(line, '^  \X*\zs\x\{7}\ze ')
    let name = empty(sha) ? matchstr(line, '^[-x+] \zs[^:]\+\ze:')
    \ : getline(search('^- .*:$', 'bn'))[2:-2]
    let uri  = get(get(g:plugs, name, {}), 'uri', '')
    if uri !~ 'github.com'
        return ''
    endif
    let repo = matchstr(uri, '[^:/]*/'..name)
    return empty(sha) ? 'https://github.com/'..repo
        \ : printf('https://github.com/%s/commit/%s', repo, sha)
endfu

