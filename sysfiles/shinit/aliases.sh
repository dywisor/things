#!/bin/sh
alias qwhich='1>/dev/null 2>&1 command -v'

qwhich shan || alias shan='nano -Y sh'

alias tmpdir='cd -- "$(mktemp -d)"'

export LS_OPTIONS='--color=auto -h'

alias ls='ls ${LS_OPTIONS}'
alias sl='ls ${LS_OPTIONS}'
alias lh='ls ${LS_OPTIONS}'

alias ll='ls ${LS_OPTIONS} -l'
alias l='ls ${LS_OPTIONS} -lAF'

alias qq=exit
alias qQ=exit
alias Qq=exit
alias QQ=exit
alias QQ=exit


export DF_OPTIONS="-h --total"
alias df='df ${DF_OPTIONS}'


alias xargs0='xargs -0'

alias chdir='cd --'
alias recd='cd -P -- "${PWD:-$(pwd)}"'

alias 'cd..'='cd ..'
# cd. is cd .., not cd $PWD
alias 'cd.'='cd ..'

#alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
## busybox ignores the "-v"
alias mvi='mv -vi'

alias sudosu='sudo su'

export GIT_LANG=C
alias git='LANG=${GIT_LANG:-C} LC_ALL=${GIT_LANG:-C} git'
alias gti='LANG=${GIT_LANG:-C} LC_ALL=${GIT_LANG:-C} git'

:
