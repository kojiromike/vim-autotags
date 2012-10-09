" vim: set sw=4 sts=4 et ft=vim :
" Script:           autotags.vim
" Author:           Basil Gor <basil.gor at gmail.com>
" Homepage:         http://github.com/basilgor/autotags
" Version:          0.2 (9 Oct 2012)
" License:          Redistribute under the same terms as Vim itself
" Purpose:          ctags and cscope tags handling
" Documentation:
"   Put autotags.vim in your ~/.vim/plugin directory, open source code and
"   press F4. Enjoy.
"
"   You can reindex sources by pressing F4 again.
"
"   Script builds and loads ctags and cscope databases via a single command.
"   All ctags and cscope files are stored in separate directory ~/.autotags by
"   default. You can set it via
"       let g:autotagsdir = $HOME."/boo"
"
"   Project root directory will be asked when indexing new project. After that
"   tags will be loaded automatically when source files somewhere in project
"   tree are opened (if path contains project root).
"
"   Exact tags location:
"   ~/.autotags/byhash/<source dir name hash>/<ctags and cscope files>
"
"   Also `origin` symlink points back to source dir
"   ~/.autotags/byhash/<source dir name hash>/origin
"
"   Tags for non-existing source directories are removed automatically
"   (checked at startup)
"
"   Also ctags file ~/.autotags/global_tags is built for /usr/include once
"
"   Below are configuration variables for the script you can set in .vimrc:
"
"   let g:autotagsdir = $HOME . "/.autotags/byhash"
"   let g:autotags_global = $HOME . "/.autotags/global_tags"
"   let g:autotags_ctags_exe = "ctags"
"   let g:autotags_ctags_opts = "--c++-kinds=+p --fields=+iaS --extra=+q"
"   let g:autotags_ctags_global_include = "/usr/include/*"
"   let g:autotags_cscope_exe = "cscope"
"   let g:autotags_cscope_file_extensions = ".cpp .cc .cxx .m .hpp .hh .h .hxx .c .idl"
"
" Dependencies:
"   ctags and cscope
"   md5sum
"   cscope_maps.vim plugin is recommended
"
" TODO:
" - Add support for other languages, supported by ctags (use cscope only for C projects)
" - Load plugin only when source code is edited
" - Script clean up

if exists("g:loaded_autotags") || &cp
    finish
endif
let g:loaded_autotags   = 0.2
let s:keepcpo           = &cpo
set cpo&vim

" Public Interface:
"
if !hasmapto('<Plug>AutotagsUpdate')
    map <unique> <F4> <Plug>AutotagsUpdate
endif

" Global Maps:
"
map <silent> <unique> <script> <Plug>AutotagsUpdate
 \  :call <SID>AutotagsUpdate()<CR>

"map <silent> <unique> <script> <Plug>AutotagsUpdate
" \  :set lz<CR>:call <SID>AutotagsUpdate()<CR>:set nolz<CR>

fun! s:Sha(val)
    return substitute(system("sha1sum", a:val), " .*", "", "")
endfun

" find and load tags, delete stale tags
fun! s:AutotagsInit()
    if !exists("g:autotagsdir")
        let g:autotagsdir = $HOME . "/.autotags/byhash"
    endif

    if !exists("g:autotags_global")
        let g:autotags_global = $HOME . "/.autotags/global_tags"
    endif

    if !filereadable(g:autotags_global)
        exe "set tags=" . g:autotags_global
    endif

    if !exists("g:autotags_ctags_exe")
        let g:autotags_ctags_exe = "ctags"
    endif

    if !exists("g:autotags_ctags_opts")
        let g:autotags_ctags_opts = "--c++-kinds=+p --fields=+iaS --extra=+q"
    endif

    if !exists("g:autotags_ctags_global_include")
        let g:autotags_ctags_global_include = "/usr/include/* /usr/include/sys/* " .
            \ "/usr/include/net* /usr/include/bits/* /usr/include/arpa/* " .
            \ "/usr/include/asm/* /usr/include/asm-generic/* /usr/include/linux/*"
    endif

    if !exists("g:autotags_cscope_exe")
        let g:autotags_cscope_exe = "cscope"
    endif

    if !exists("g:autotags_cscope_file_extensions")
        let g:autotags_cscope_file_extensions = ".cpp .cc .cxx .m .hpp .hh .h .hxx .c .idl"
    endif

    let s:cscope_file_pattern = '.*\' . join(split(g:autotags_cscope_file_extensions, " "), '\|.*\')

    " remove stale tags
    for entry in split(system("ls " . g:autotagsdir), "\n")
        let s:path = g:autotagsdir . "/" . entry
        if getftype(s:path) == "dir"
            let s:origin = s:path . "/origin"
            if getftype(s:origin) == 'link' && !isdirectory(s:origin)
                echomsg "deleting stale tags for " .
                    \ substitute(system("readlink '" . s:origin . "'"), "\n.*", "", "")
                call system("rm -r '" . s:path . "'")
            endif
        endif
    endfor

    " find autotags subdir
    let s:dir = getcwd()
    while s:dir != "/"
        if getftype(g:autotagsdir . '/' . s:Sha(s:dir)) == "dir"
            let s:autotags_subdir = g:autotagsdir . '/' . s:Sha(s:dir)
            "echomsg "autotags subdir exist: " . s:autotags_subdir
            break
        endif
        let s:dir = substitute(system("dirname '" . s:dir . "'"), "\n.*", "", "")
    endwhile

    " search ctags in current tree
    if filereadable(findfile("tags", ".;"))
        let s:ctagsfile = findfile("tags", ".;")
        exe "set tags+=" . s:ctagsfile

        if s:ctagsfile == "tags"
            let s:ctagsfile = getcwd() . '/' . s:ctagsfile
        endif
        "echomsg "ctags: " . s:ctagsfile
    else
        " look for autotags
        if exists("s:autotags_subdir") && filereadable(s:autotags_subdir . '/tags')
            let s:ctagsfile = s:autotags_subdir . '/tags'
            exe "set tags+=" . s:ctagsfile
            "echomsg "ctags: " . s:ctagsfile
        endif
    endif

    " search cscope db in current tree
    if filereadable(findfile("cscope.out", ".;"))
        let s:cscopedir = findfile("cscope.out", ".;")
        exe "cs add " . s:cscopedir

        if s:cscopedir == "cscope.out"
            let s:cscopedir = getcwd() . "/" . s:cscopedir
        endif
        "echomsg "cscope: " . s:cscopedir
        let s:cscopedir = substitute(s:cscopedir, "cscope.out", "", "")
    else
        " look for autotags
        if exists("s:autotags_subdir") && filereadable(s:autotags_subdir . '/cscope.out')
            let s:cscopedir = s:autotags_subdir
            exe "cs add " . s:autotags_subdir . '/cscope.out'
            "echomsg "cscope: " . s:autotags_subdir . '/cscope.out'
        endif
    endif
endfun

fun! s:AutotagsUpdate()
    if !exists("s:autotags_subdir") ||
       \ !isdirectory(s:autotags_subdir) ||
       \ !isdirectory(s:autotags_subdir . '/origin')
        let s:sourcedir = getcwd()

        call inputsave()
        let s:sourcedir = input("build tags for: ", s:sourcedir, "file")
        call inputrestore()

        if !isdirectory(s:sourcedir)
            echomsg "directory " . s:sourcedir . " doesn't exist"
            unlet s:sourcedir
            return
        endif

        let s:sourcedir = substitute(s:sourcedir, "\/$", "", "")

        let s:autotags_subdir = g:autotagsdir . '/' . s:Sha(s:sourcedir)
        if !mkdir(s:autotags_subdir, "p")
            echomsg "cannot create dir " . s:autotags_subdir
            return
        endif

        call system("ln -s '" . s:sourcedir . "' '" . s:autotags_subdir . "/origin'")
    endif

    if !filereadable(g:autotags_global)
        echomsg " "
        echomsg "updating global ctags " . g:autotags_global . " for " .
            \ g:autotags_ctags_global_include
        echomsg system("nice -15 " . g:autotags_ctags_exe . " " .
            \ g:autotags_ctags_opts . " -f '" . g:autotags_global . "' " .
            \ g:autotags_ctags_global_include)
    endif

    if !exists("s:sourcedir")
        let s:sourcedir = substitute(system("readlink '" . s:autotags_subdir . "/origin'"), "\n.*", "", "")
    endif

    if !exists("s:ctagsfile")
        let s:ctagsfile = s:autotags_subdir . "/tags"
    endif

    echomsg "updating ctags " . s:ctagsfile ." for " . s:sourcedir
    echomsg system("nice -15 " . g:autotags_ctags_exe . " -R " .
        \ g:autotags_ctags_opts . " -f '" . s:ctagsfile . "' '" . s:sourcedir ."'")

    if !exists("s:cscopedir")
        let s:cscopedir = s:autotags_subdir
    endif

    echomsg "updating cscopedb in " . s:cscopedir ." for " . s:sourcedir
    echomsg system("cd '" . s:cscopedir . "' && nice -15 find '" . s:sourcedir . "' " .
        \ "-not -regex '.*\\.git.*' -regex '" . s:cscope_file_pattern . "' -fprint cscope.files")
    echomsg system("cd '" . s:cscopedir . "' && nice -15 " . g:autotags_cscope_exe . " -b -q")

    exe "cs kill -1"
    exe "cs add " . s:cscopedir . "/cscope.out"

    exe "set tags=" . g:autotags_global
    exe "set tags+=" . s:ctagsfile

    echomsg "tags updated"
endfun

fun! s:AutotagsRemove()
    if exists("s:autotags_subdir")
        echomsg "deleting autotags " . s:autotags_subdir . " for " .
            \ substitute(system("readlink '" . s:autotags_subdir . "/origin'"), "\n.*", "", "")
        call system("rm -r '" . s:autotags_subdir . "'")
        exe "set tags=" . g:autotags_global
        exe "cs kill -1"
        exe "cs reset"
    endif
endfun

call <SID>AutotagsInit()
let &cpo= s:keepcpo
unlet s:keepcpo
