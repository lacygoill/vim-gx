vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

const DIR: string = getenv('XDG_RUNTIME_VIM') ?? '/tmp'

# Interface {{{1
def gx#open(in_term = false) #{{{2
    var url: string
    if mode() =~ "^[vV\<c-v>]$"
        var reg_save: dict<any> = getreginfo('"')
        norm! gvy
        url = @"
        setreg('"', reg_save)
    else
        url = GetUrl()
    endif

    if empty(url)
        return
    endif

    # [some book](~/Dropbox/ebooks/Later/Algo To Live By.pdf#page=123)
    if match(url, '^\%(https\=\|ftps\=\|www\)://') == -1
        var pagenr: number = matchstr(url, '#page=\zs\d\+$')->str2nr()
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
        var ext: string = fnamemodify(url, ':e')
        var cmd: string = get({pdf: 'zathura'}, ext, 'xdg-open')
        if cmd == 'zathura' && pagenr > 0
            cmd ..= ' --page=' .. pagenr
        endif
        cmd ..= ' ' .. shellescape(url) .. ' &'
        sil system(cmd)
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
            sil system('tmux split-window -c ' .. shellescape(DIR))
            # maximize the pane
            sil system('tmux resize-pane -Z')
            # start `w3m`
            sil system('tmux send-keys web \ ' .. shellescape(url) .. ' Enter')
            #                               │{{{
            #                               └ without the backslash,
            #
            # `tmux` would think  it's a space to separate the  arguments of the
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
            sil system('xdg-open ' .. shellescape(url))
        endif
    endif
enddef
# }}}1
# Core {{{1
def GetUrl(): string #{{{2
    # https://github.com/junegunn/vim-plug/wiki/extra
    if &filetype == 'vim-plug'
        return GetUrlVimPlug()
    endif

    var url: string
    var col_start_link: number
    var col_start_url: number
    var col_end_url: number
    var line: string = getline('.')
    var pos: list<number> = getcurpos()
    # [link](url)
    var pat: string = '!\=\[.\{-}\]' .. '\%((.\{-})\|\[.\{-}\]\)'
    norm! 0
    var flags: string = 'cW'
    var curlnum: number = line('.')
    var g: number = 0 | while search(pat, flags, curlnum) > 0 && g < 100 | g += 1
        col_start_link = col('.')
        norm! %l
        col_start_url = col('.')
        norm! %
        col_end_url = col('.')
        if pos[2] >= col_start_link && pos[2] <= col_end_url
            var idx1: number = charidx(line, col_start_url + 1)
            var idx2: number = charidx(line, col_end_url)
            url = line[idx1 - 1 : idx2 - 1]
            break
        endif
        flags = 'W'
    endwhile
    setpos('.', pos)

    if url != ''
        var arg: dict<any> = {
            line: line,
            url: url,
            col_start_link: col_start_link,
            col_start_url: col_start_url,
            col_end_url: col_end_url,
            }
        return GetUrlMarkdownStyle(arg)
    else
        return GetUrlRegular()
    endif
enddef

def GetUrlMarkdownStyle(arg: dict<any>): string #{{{2
    var line: string = arg.line
    var url: string = arg.url
    var col_start_link: number = arg.col_start_link
    var col_start_url: number = arg.col_start_url
    var col_end_url: number = arg.col_end_url
    # [text](link)
    if strpart(line, col_start_url - 1)[0] == '('
        # This is [an example](http://example.com/ "Title") inline link.
        url = url->substitute('\s*".\{-}"\s*$', '', '')

    # [text][ref]
    else
        var ref: string
        # Visit [Daring Fireball][id] for more information.
        # [id]: https://daringfireball.net/projects/markdown/syntax#link
        if url == ''
            ref = matchstr(line,
                '\%' .. (col_start_link + 1) .. 'c.*\%' .. (col_start_url - 1) .. 'c')
        else
            ref = url
        endif
        var cml: string
        if &filetype == 'markdown'
            cml = ''
        else
            cml = '\V' .. matchstr(&l:cms, '\S*\ze\s*%s')->escape('\') .. '\m'
        endif
        url = getline('.', '$')
            ->filter((_, v: string): bool =>
                v =~ '^\s*' .. cml .. '\s*\c\V[' .. ref .. ']:'
            )->get(0, '')
            ->matchstr('\[.\{-}\]:\s*\zs.*')
        # [foo]: http://example.com/  "Optional Title Here"
        # [foo]: http://example.com/  'Optional Title Here'
        # [foo]: http://example.com/  (Optional Title Here)
        var pat: string = '\s\+\(["'']\).\{-}\1\s*$'
            .. '\|\s\+(.\{-})\s*$'
        url = url
            ->substitute(pat, '', '')
            # [id]: <http://example.com/>  "Optional Title Here"
            ->trim('<>')
    endif
    return url
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

def GetUrlVimPlug(): string #{{{2
    var line: string = getline('.')
    var sha: string = matchstr(line, '^  \X*\zs\x\{7}\ze ')
    var name: string = empty(sha)
        ?     matchstr(line, '^[-x+] \zs[^:]\+\ze:')
        :     search('^- .*:$', 'bn')->getline()[2 : -2]
    var uri: string = get(g:plugs, name, {})->get('uri', '')
    if uri !~ 'github.com'
        return ''
    endif
    var repo: string = matchstr(uri, '[^:/]*/' .. name)
    return empty(sha)
        ?     'https://github.com/' .. repo
        :     printf('https://github.com/%s/commit/%s', repo, sha)
enddef

