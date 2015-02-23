#!/bin/sh
f=
for f in "${HOME}/.ashrc" /etc/ashrc; do
   if [ -r "${f}" ]; then
      . "${f}" || :
      break
   fi
done
unset -v f
