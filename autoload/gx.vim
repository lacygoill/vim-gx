" Interface {{{1
fu! gx#open(in_term, ...) abort "{{{2
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

    if match(url, '\v^%(https?|ftp|www)') ==# -1
        " expand a possible tilde in the path to a local file
        let url = expand(url)
        if !filereadable(url)
            return
        endif
        let ext = fnamemodify(url, ':e')
        let cmd = get({'pdf': 'zathura'}, ext, 'xdg-open')
        sil call system(cmd.' '.url.' &')
    else
        if a:in_term
            " We could pass the shell command we want to execute directly to
            " `tmux split-window`, but the pane would be closed immediately.
            " Because by default, tmux closes a window/pane whose shell command
            " has completed:
            "         When the shell command completes, the window closes.
            "         See the remain-on-exit option to change this behaviour.
            "
            " For more info, see `man tmux`, and search:
            "
            "     new-window
            "     split-window
            "     respawn-pane
            "     set-remain-on-exit
            sil call system('tmux split-window -c '.$XDG_RUNTIME_VIM')
            " maximize the pane
            sil call system('tmux resize-pane -Z')
            " start `w3m`
            sil call system('tmux send-keys web \ '.shellescape(url).' Enter')
            "                                    │
            "                                    └─ without the backslash, `tmux` would think
            "                                    it's a space to separate the arguments of the
            "                                    `send-keys` command; therefore, it would remove it
            "                                    and type:
            "                                                weburl
            "                                    instead of:
            "                                                web url
            "
            "                                    The backslash is there to tell it's a semantic space.
        else
            sil call system('xdg-open '.shellescape(url))
        endif
    endif
endfu

" Util {{{1
fu! s:get_url() abort "{{{2
    " https://github.com/junegunn/vim-plug/wiki/extra
    if &ft is# 'vim-plug'
        let line = getline('.')
        let sha  = matchstr(line, '^  \X*\zs\x\{7}\ze ')
        let name = empty(sha) ? matchstr(line, '^[-x+] \zs[^:]\+\ze:')
        \ : getline(search('^- .*:$', 'bn'))[2:-2]
        let uri  = get(get(g:plugs, name, {}), 'uri', '')
        if uri !~ 'github.com'
            return ''
        endif
        let repo = matchstr(uri, '[^:/]*/'.name)
        return empty(sha) ? 'https://github.com/'.repo
        \ : printf('https://github.com/%s/commit/%s', repo, sha)

    else
        let url = expand('<cWORD>')
        if url =~# 'http\|ftp\|www'
            " Which characters make a URL invalid?
            " https://stackoverflow.com/a/13500078

            " remove everything before the first `http`, `ftp` or `www`
            let url = substitute(url, '\v.{-}\ze%(http|ftp|www)', '', '')

            " remove everything after the first `⟩`, `>`, `)`, `]`, `}`
            let url = substitute(url, '\v.{-}\zs[⟩>)\]}].*', '', '')

            " remove everything after the last `"`
            return substitute(url, '\v".*', '', '')

        else
            " [text][ref]
            " [text](link)
            let pat  = '\[\=.*\%'.col('.').'c.*\]\&\[.\{-}\]'
            let pat .= '\%((.\{-})\|\[.\{-}\]\)'
            let url = matchstr(getline('.'), pat)

            " [text][ref]
            if url =~# '^\[.\{-}\]\[.\{-}\]'
                let url = matchstr(url, '^\[.\{-}\]\zs\[.\{-}\]$')
                let url = filter(getline(line('.'), '$'), {i,v -> v =~# '^\c\V'.url.':'})
                let url = matchstr(get(url, 0, ''), '\[.\{-}\]:\s*\zs.*')
                return substitute(url, '\s*".\{-}"\s*$', '', '')

            " [text](link)
            " [text](path_to_local_file)
            elseif url =~# '^\[.\{-}\](.\{-})'
                let url = matchstr(url, '^\[.\{-}\](\zs.*\ze)$')
                let url = substitute(url, '\s*".\{-}"\s*$', '', '')
                return url =~# '\.pdf$'
                \ ?        ''
                \ :        url
            else
                return ''
            endif
        endif
    endif
endfu

