[ -n "${PATH_BAK-}" ] || PATH_BAK="${PATH-}"

if [ -z "${EUID-}" ]; then
   EUID="$(id -u 2>/dev/null)" || :
   [ -z "${EUID}" ] || export EUID
fi

if [ -z "${UID-}" ]; then
   UID="$(id -ru 2>/dev/null)" || :
   [ -z "${UID}" ] || export UID
fi

if [ -z "${USER-}" ]; then
   USER="$(id -rnu 2>/dev/null)" || :
   [ -z "${USER}" ] || export USER
fi


TMPDIR=/tmp
PRIV_TMPDIR=
if [ -n "${USER}" ]; then

   if [ -z "${HOME-}" ]; then
      if command -v getent 1>/dev/null 2>&1; then
         HOME="$( getent passwd "${USER}" | awk -F : '{ print $6; exit; }' )"

      elif [ -r /etc/passwd ]; then
         HOME="$( \
            awk -F : -v user="${USER}" \
               '($1 == user) { print $6; exit; }' /etc/passwd )"
      fi
      ## dscl, pw
      [ -z "${HOME}" ] || export HOME
   fi

   for PRIV_TMPDIR in \
      "/var/tmp/users/${USER}" \
      "/tmp/users/${USER}" \
      _
   do
      if [ "${PRIV_TMPDIR}" = "_" ]; then
         PRIV_TMPDIR=
         break

      elif { touch "${PRIV_TMPDIR}/.keep"; } 2>/dev/null; then
         TMPDIR="${PRIV_TMPDIR}"
         break
      fi
   done

fi
export TMPDIR

if [ -z "${PYTHONSTARTUP-}" ] && [ -r /etc/pythonrc ]; then
   export PYTHONSTARTUP=/etc/pythonrc
fi



# int shinit_PATH_has ( dir )
shinit_PATH_has() {
   [ -n "${1-}" ] || return 0
   case ":${PATH-}:" in
      *":${1}:"*)
         return 0
      ;;
      *)
         return 1
      ;;
   esac
}

# void shinit_PATH_add ( *dirs )
shinit_PATH_add() {
   while [ ${#} -gt 0 ]; do
      shinit_PATH_has "${1}" || PATH="${1}${PATH:+:}${PATH-}"
      shift
   done
}

# void shinit_PATH_addif ( *dirs )
shinit_PATH_addif() {
   while [ ${#} -gt 0 ]; do
      if ! shinit_PATH_has "${1}" && [ -d "${1}" ]; then
         PATH="${1}${PATH:+:}${PATH-}"
      fi
      shift
   done
}

# extend PATH

if [ -d /var/local/scripts ]; then
   shinit_PATH_add /var/local/scripts
   if [ "${USER:-X}" = "root" ]; then
      shinit_PATH_addif /var/local/scripts/root
   fi
fi

if [ -d /sh ]; then
   if [ ! -h /sh ] || [ ! -d /var/local/scripts ]; then
      shinit_PATH_add /sh
      [ "${USER:-X}" != "root" ] || shinit_PATH_addif /sh/root
   fi
fi

if [ -n "${HOME-}" ] && [ -d "${HOME}/bin" ]; then
   shinit_PATH_add   "${HOME}/bin"
   shinit_PATH_addif "${HOME}/bin/wrapper"
   shinit_PATH_addif "${HOME}/bin/alias"
fi

export PATH

unset -f shinit_PATH_has
unset -f shinit_PATH_add
unset -f shinit_PATH_addif


if [ "X@@USE_TZFILE@@" = "Xy" ] && [ -r /etc/TZ ]; then
   _TZ=
   if { read -r _TZ < /etc/TZ; } 2>/dev/null && [ -n "${_TZ}" ]; then
      export TZ="${_TZ}"
   fi
   unset -v _TZ
fi

:
