#!/bin/sh
# Usage: [TC_ROOT="<dir>..."] get-toolchain.sh [-x] <arch>[-<libc>]
#
#  Multicall script:
#   Behaves as if "-x" was specified if the script name
#   ends with "-x" or "cross" (e.g. get-tc-x).
#
set -u
INITIAL_WORKDIR="${PWD}"

DEFAULT_TC_ROOT_DIRS="/usr/local/toolchain /opt/toolchain"

TC_ROOT_DIRS="${TC_ROOT} ${DEFAULT_TC_ROOT_DIRS}"

DEFAULT_LIBC_LIST="uclibc musl glibc"
# newlib, eglibc and whatnot are rather unusual


print() { printf "%s\n" "${*}"; }

if [ "${DEBUG:-X}" = "y" ]; then
debug_print() { print  "${*}" 1>&2; }
else
debug_print() { return 0; }
fi

get_arch_variants() {
   while [ ${#} -gt 0 ]; do
      case "${1}" in
         armv5tel|dream*|sheeva*|guru*|dockstar|kirkwood)
            print  armv5tel armv5te
         ;;
         ds?14|ds?14se)
            print  \
               armv7l_pj4 armv7l-pj4 armv7l \
               armv7a_pj4 armv7a-pj4 armv7a
         ;;
         *)
            print  "${1}"
         ;;
      esac
      shift
   done
}

get_libc_variants() {
   print  "${*}"
}

get_xchain__check() {
   local d

   while [ $# -gt 0 ]; do
      d="${1}"
      [ ! -h "${d}" ] || d="$(readlink -f "${d}")"

      debug_print  "Checking: ${d}"

      if [ -d "${d}" ]; then
         debug_print  "Found: ${d}"
         xarch="${my_arch:?}"
         xlibc="${my_libc:?}"
         xchain="${d}"
         return 0
      fi

      shift
   done

   return 1
}

get_xchain() {
   xarch=
   xchain=
   xlibc=
   local archv
   local libcv
   local my_arch
   local my_libc
   local my_tc_root

   archv="$(get_arch_variants ${1})"
   libcv="$(get_libc_variants ${2})"

   for my_tc_root in ${TC_ROOT_DIRS?}; do
      case "${my_tc_root}" in
         /*)
            :
         ;;
         *)
            my_tc_root="${INITIAL_WORKDIR}/${my_tc_root}"
         ;;
      esac

      if cd -P "${my_tc_root}" 2>/dev/null; then
         # allows gliobbing in $archv, $libcv
         # and filters out non-existent tc rootfs

         for my_arch in ${archv}; do
            for my_libc in ${libcv}; do
               if get_xchain__check \
                  "${my_tc_root}/${my_arch}-${my_libc}" \
                  "${my_tc_root}/${my_arch}/${my_libc}"
               then
                  return 0
               fi
            done
         done

      else
         debug_print  "not-a-dir: ${my_tc_root}"
      fi
   done

   debug_print  "No toolchain found!"
   return 1
}

want_cross=false
case "${1-}" in
   '-x')
      want_cross=true
      shift
   ;;
esac

case "${0##*/}" in
   *cross|*-x)
      want_cross=true
   ;;
esac

if [ -z "${1-}" ]; then
   print  "Missing toolchain name arg!" 1>& 2
   print  "Usage: ${0} [-x] <arch>[-<libc>]" 1>&2
   exit 64
fi

arch_in="${1%%-*}"
# vendor/os/libc:
libc_in="${1#*-}"
[ "${libc_in}" != "${arch_in}" ] || libc_in="${DEFAULT_LIBC_LIST}"


get_xchain "${arch_in}" "${libc_in}" || exit 5
: ${xchain:?} ${xarch:?}

if ! ${want_cross}; then
   print  "${xchain}"

else
   case "${xarch}" in
      arm*)
         xname=arm-linux
      ;;
      amd64*)
         xname=x86_64-linux
      ;;
      *)
         xname="${xarch}-linux"
      ;;
   esac

   xcross="${xchain}/bin/${xname}-"
   readlink -f "${xcross}"
   if [ -x "${xcross}gcc" ]; then
      exit 0
   else
      debug_print  "no-gcc-found: ${xcross}"
      exit 4
   fi
fi
