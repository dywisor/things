#!/bin/sh

print_nanorc_includes() {
   printf '\n\n# includes\n'
   while [ ${#} -gt 0 ]; do
      printf 'include %s%s%s\n' "\"" "${1}" "\""
      shift
   done
}


if [ -n "${ROOT}" ]; then

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

         print_nanorc_includes "${@}" >> "${D}/nanorc" || \
            die "Failed to append includes to ${D}/nanorc "
      fi
   fi
fi
