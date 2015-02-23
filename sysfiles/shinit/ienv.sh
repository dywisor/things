#!/bin/sh
# Should be loaded after env.sh, aliases.sh
#

newdir() {
   [ -n "${1-}" ] && mkdir -p -- "${1}" && cd -- "${1}"
}

if [ -n "${HOME-}" ] && [ -r "${HOME}/.dircolors" ]; then
   eval "$(dircolors -b "${HOME}/.dircolors")"
else
   eval "$(dircolors -b)"
fi

if [ -z "${CPUCOUNT-}" ] && [ -r /proc/cpuinfo ]; then
   CPUCOUNT="$( \
      2>/dev/null awk \
         'BEGIN{n=0;} /^processor\s*:/ {n=n+1;} END{printf("%d\n",n);}' \
         /proc/cpuinfo )"
   : "${CPUCOUNT:=1}"
fi

:
