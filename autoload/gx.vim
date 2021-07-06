vim9script noclear

const DIR: string = getenv('XDG_RUNTIME_VIM') ?? '/tmp'

# Interface {{{1
def gx#open(in_term = false) #{{{2
    var url: string
    if mode() =~ "^[vV\<C-V>]$"
        var reg_save: list<dict<any>> = [getreginfo('0'), getreginfo('1')]
        try
            normal! gvy
            url = @"
        finally
            setreg('0', reg_save[0])
            setreg('"', reg_save[1])
        endtry
    else
        url = GetUrl()
    endif

    if empty(url)
        return
    endif

    # [some book](~/Dropbox/ebooks/Later/Algo To Live By.pdf#page=123)
    if match(url, '^\%(https\=\|ftps\=\|www\)://') == -1
        var pagenr: number = url->matchstr('#page=\zs\d\+$')->str2nr()
        # Don't use `expand()`!{{{
        #
        # We don't want  something like `#anchor` to be replaced  by the path to
        # the alternate file.
        #
        # We could also do sth like:
        #
        #     url = fnameescape(url)->expand()
        #
        # Not sure whether it's totally equivalent though...
        #}}}
        url = url
            ->substitute('^\~', $HOME, '')
            ->substitute('#page=\d\+$', '', '')
        if !filereadable(url)
            return
        endif
        var ext: string = url->fnamemodify(':e')
        var cmd: string = get({pdf: 'zathura'}, ext, 'xdg-open')
        if cmd == 'zathura' && pagenr > 0
            cmd ..= ' --page=' .. pagenr
        endif
        cmd ..= ' ' .. shellescape(url) .. ' &'
        silent system(cmd)
    else
        if in_term
            # Could we pass the shell command to `$ tmux split-window` directly?{{{
            #
            # Yes but the pane would be closed immediately.
            # Because by default, tmux closes  a window/pane whose shell command
            # has completed:
            #
            #    > When the shell command completes, the window closes.
            #    > See the remain-on-exit option to change this behaviour.
            #
            # For more info, see `man tmux`, and search:
            #
            #     new-window
            #     split-window
            #     respawn-pane
            #     set-remain-on-exit
            #}}}
            silent system('tmux split-window -c ' .. shellescape(DIR))
            # maximize the pane
            silent system('tmux resize-pane -Z')
            # start `w3m`
            silent system('tmux send-keys web \ ' .. shellescape(url) .. ' Enter')
            #                                  │{{{
            #                                  └ without the backslash,
            #
            # Tmux would  think it's a  space to  separate the arguments  of the
            # `send-keys` command; therefore, it would remove it and type:
            #
            #             weburl
            #
            # instead of:
            #
            #             web url
            #
            # The backslash is there to tell it's a semantic space.
            #}}}
        else
            silent system('xdg-open ' .. shellescape(url))
        endif
    endif
enddef
# }}}1
# Core {{{1
def GetUrl(): string #{{{2
    var inside_brackets: string
    var link_colstart: number
    var brackets_colstart: number
    var brackets_colend: number
    var line: string = getline('.')
    var pos: list<number> = getcurpos()
    # [link](url)  (or [link][id])
    var pat: string = '!\=\[.\{-1,}\]' .. '\%((.\{-1,})\|\[.\{-1,}\]\)'
    normal! 0
    var flags: string = 'cW'
    var curlnum: number = line('.')
    var g: number = 0 | while search(pat, flags, curlnum) > 0 && g < 100 | ++g
        # [link](inside_brackets)
        # ^
        link_colstart = col('.')

        normal! %ll
        # [link](inside_brackets)
        #        ^
        brackets_colstart = col('.')

        normal! h%h
        # [link](inside_brackets)
        #                      ^
        brackets_colend = col('.')

        if link_colstart <= pos[2] && pos[2] <= brackets_colend
            var idx1: number = charidx(line, brackets_colstart - 1)
            var idx2: number = charidx(line, brackets_colend - 1)
            inside_brackets = line[idx1 : idx2]
            break
        endif
        flags = 'W'
    endwhile
    setpos('.', pos)

    if inside_brackets != ''
        return GetUrlMarkdownStyle(line, inside_brackets, brackets_colstart)
    else
        return GetUrlRegular()
    endif
enddef

def GetUrlMarkdownStyle( #{{{2
    line: string,
    inside_brackets: string,
    brackets_colstart: number
): string

    # [link](inside_brackets){{{
    #
    #     This is [an example](http://example.com/ "Title") inline link.
    #}}}
    if strpart(line, brackets_colstart - 2)[0] == '('
        return inside_brackets
            ->substitute('\s*".\{-}"\s*$', '', '')

    # [link][id]{{{
    #
    #     Visit [Daring Fireball][id] for more information.
    #     [id]: https://daringfireball.net/projects/markdown/syntax#link
    #}}}
    else
        var cml: string = &filetype == 'markdown'
            ?     ''
            :     '\V' .. &commentstring->matchstr('\S*\ze\s*%s')->escape('\') .. '\m'
        var noise: string = '\s\+\(["'']\).\{-}\1\s*$'
            .. '\|\s\+(.\{-})\s*$'

        return getline('.', '$')
            ->filter((_, v: string): bool =>
                v =~ '^\s*' .. cml .. '\s*\c\V[' .. inside_brackets .. ']:')
            ->get(0, '')
            ->matchstr('\[.\{-}\]:\s*\zs.*')
            # Remove possible noise:{{{
            #
            #     [id]: http://example.com/  "Optional Title Here"
            #                              ^---------------------^
            #     [id]: http://example.com/  'Optional Title Here'
            #                              ^---------------------^
            #     [id]: http://example.com/  (Optional Title Here)
            #                              ^---------------------^
            #     [id]: <http://example.com/>  "Optional Title Here"
            #           ^                   ^
            #}}}
            ->substitute(noise, '', '')
            ->trim('<>')
    endif
enddef

def GetUrlRegular(): string #{{{2
    # Do *not* use `<cfile>`.{{{
    #
    # Sometimes, it wouldn't handle some urls correctly.
    #
    #     https://www.youtube.com/watch?v=InAaCKqUmjE&t=90s
    #                                  ├────────────┘├────┘
    #                                  │             └ when the cursor is somewhere here,
    #                                  │               expand('<cfile>') is t=90s
    #                                  │
    #                                  └ when the cursor is somewhere here,
    #                                    expand('<cfile>') is v=InAaCKqUmjE
    #}}}
    var url: string = expand('<cWORD>')
    var pat: string = '\%(https\=\|ftps\=\|www\)://'
    if url !~ pat
        return ''
    endif

    # Which characters make a URL invalid?
    # https://stackoverflow.com/a/13500078

    # remove everything before the first `http`, `ftp` or `www`
    url = url->substitute('.\{-}\ze' .. pat, '', '')

    # remove everything after the first `⟩`, `>`, `)`, `]`, `}`, backtick
    # but some wikipedia links contain parentheses:{{{
    # https://en.wikipedia.org/wiki/Daemon_(computing)
    #
    # In those cases,  we need to make an exception,  and not remove the
    # text after the closing parenthesis.
    #}}}
    var chars: string = match(url, '(') == -1
        ? '[]⟩>)}`]'
        : '[]⟩>}`]'

    return url
        ->substitute('.\{-}\zs' .. chars .. '.*', '', '')
        # remove everything after the last `"`
        ->substitute('".*', '', '')
enddef

