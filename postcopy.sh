#!/bin/sh

print_nanorc_includes() {
   printf '\n\n# includes\n'
   while [ ${#} -gt 0 ]; do
      printf 'include %s%s%s\n' "\"" "${1}" "\""
      shift
   done
}

# MODE==all:
if [ -n "${ROOT?}" ]; then

   if [ -f "${S}/nanorc" ]; then
      autodie test -f "${D}/nanorc"   ## and same file (content)

      set --
      for f in \
         "${ROOT%/}/usr/share/nano/"*".nanorc" \
         "${ROOT%/}/etc/highlight-nano.d/"*".nanorc" \
         "${ROOT%/}/etc/nano/"*".nanorc"
      do
         if [ -f "${f}" ] || [ -h "${f}" ]; then
            set -- "${@}" "${f#${ROOT%/}}"
         fi
      done

      if [ ${#} -eq 0 ]; then
         :

      elif [ "${FAKE_MODE:-X}" = "y" ]; then
         printf '%s\n' "*** nanorc includes ***"
         print_nanorc_includes "${@}"
         printf '%s\n' "*** EOF ***"

      else

         print_nanorc_includes >> "${D}/nanorc" || \
            die "Failed to append includes to ${D}/nanorc "
      fi
   fi
fi

# MODE=system:
if [ "${MODE:?}" = "system" ]; then

   # some distros use /etc/bash.bashrc, some use /etc/bash/bashrc
   if [ -f "${S}/bash/bashrc" ] && [ ! -f "${S}/bash.bashrc" ]; then
      dfile="${D}/bash.bashrc"

      if [ -h "${dfile}" ]; then
         autodie rm -- "${dfile}"

      elif [ -e "${dfile}" ]; then
         if [ -e "${dfile}.dist" ]; then
            die "cannot move ${dfile}"
         else
            autodie mv -- "${dfile}" "${dfile}.dist"
         fi
      fi

      __cmd__ ln -s -- bash/bashrc "${dfile}" || \
      target_copyfile "${D}/bash/bashrc" "${dfile}"
   fi

   if [ -f "${S}/locale.conf" ]; then
      target_dodir "${D}/env.d"
      target_rmfile "${D}/env.d/02locale"
      autodie ln -s -- ../locale.conf
   fi

fi
