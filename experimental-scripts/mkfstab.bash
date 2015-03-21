#!/bin/bash
#  fstab creation helper
#
# Copyright (C) 2014 André Erdmann <dywi@mailerd.de>
# This script is dual-licensed and is distributed under the terms
# of either
#   (a) the GNU Affero General Public License, version 3 or later, or
#   (b) the BSD 2-clause License,
# at your own discretion.
#
set -efeu
SCRIPT_FILE="${BASH_SOURCE:-${0}}"
SCRIPT_NAME="${SCRIPT_FILE##*/}"
# ----------------------------------------------------------------------------
mkfstab_print_help() {
cat << EOF | sed -r -e '/^[#]/{s=^[#]\s*$==;s=^[#]\s==;}'
# Usage: ${SCRIPT_NAME:-mkfstab} [-h] [-d <dir>] {<file>|-E <entry>|-s}
#
# Merges and formats fstab files.
#
# Entries can be read from files and specified on the command line
# with the -E option. Later entries override earlier ones, but their
# order is preserved. Empty lines and comments are discarded.
#
#
# Entry syntax:
# * <fs> <mp> <fstype> [<options> [<dump> [<pass>]]]
#    More or less a usual fstab line.
#
#    Default values:
#    * options := "defaults"
#    * dump    := "0"
#    * passno  := "0"
#
# * @bind <from> <to> [<options>]
#    Shorthand for
#      <from> <to> none bind[,<options>] 0 0
#
# * @tmpfs <mp> [<mode> [<size> [<options> [<name>]]]]
#    Shorthand for
#      <name> <mp> tmpfs [mode=]<mode>[,size=<size>][,<options>] 0 0
#
#    The optional fields accept "-" as "use default" value.
#    <name> defaults to "tmpfs" and <mode> defaults to "1777".
#
# * @swap <fs> [<options>]
#    Shorthand for
#     <fs> none swap sw[,<options>] 0 0
#
#
# Options:
#   -h, --help            print the help message and exit
#   -E, --entry  <entry>  fstab entry, fields may also be separated with "|"
#   -O, --outfile <file>  write the resulting fstab file to <file>
#                          instead of stdout
#   -d, --makedirs <dir>  create mountpoints in <dir> if necessary
#                          replaces symlinks, <dir> must already exist!
#   -F, --makedirs-backup <file>
#                         also create a script that reverts changes
#                          done by --makedirs
#   -s, --ignore-missing  ignore missing files
#
#
# Example:
#    mkfstab --makedirs "\$TARGET_DIR" \\
#      system/fstab.in \\
#      --ignore-missing output/build/*/fstab.in \\
#      -E '@tmpfs|/run|0755'
#
#   Reads entries from system/fstab.in (which has to exist) and
#   all fstab.in files found in output/build/*/ (which don't have to exist),
#   and adds a tmpfs-mount entry for /run with mode=0755.
#   All mountpoints are created \$TARGET_DIR and the resulting fstab file
#   is written to stdout.
#
#   The example assumes that globbing is enabled in the current shell,
#   which is the default behavior.
EOF
}
# ----------------------------------------------------------------------------
#
# Limitations:
# * --makedirs:
#    - creates all mountpoints, even if they are effectively unreachable
#       (e.g. creates /tmp/foo even if /tmp is a mountpoint on its own)
#       Could be fixed by searching for parent mounts in the mountpoint list,
#       checking whether the filesystem type is volatile (e.g. tmpfs) and
#       whether the mount options contain "noauto"/"nofail".
#
# * --makedirs-backup:
#    - Does not restore permissions/ownership/times/...
#       Not a real issue because only symlinks are restored and
#       buildroot chowns them before creating filesystem images
#
# * the <mountpoint> is discarded for swap entries (always none),
#   won't fix unless convinced otherwise...
# ---
#
# keep the code bash-free where possible, exceptions:
# * arrays for storing entry information + wrapper functions
# * arrays for --makescript-backup
# * strfeed_cmd()
#
#
# ----------------------------------------------------------------------------

if ! [ ${BASH_VERSINFO[0]} -ge 4 ]; then
   echo "script needs bash >= 4, not ${BASH_VERSION}." 1>&2
   exit 99
fi

# %ENTRY_LIST: list of (entry_type,key) pairs
declare -a ENTRY_LIST=()

# %MP_ENTRY_TABLE: mountpoint -> entry (fields are whitespace-separated)
#  (entry also includes the mountpoint)
declare -A MP_ENTRY_TABLE=()

# %SWAP_ENTRY_TABLE: swap device -> mount options
declare -A SWAP_ENTRY_TABLE=()


# link_name => link_target
declare -A MAKEDIRS_BACKUP_SYMLINK=()
# dirpath => ""
declare -A MAKEDIRS_BACKUP_RMDIR=()


# format str for entries
#  <fs> <mp> <fstype> <options> <dump> <pass>
ENTRY_FMT_COMMON="%-16s %-16s %-8s"
ENTRY_FMT="${ENTRY_FMT_COMMON} %-24s %-6s %s"

# slightly different format str for the entry header line that keeps
# the line length below 80 chars
HEADER_ENTRY_FMT="${ENTRY_FMT_COMMON} %-22s %s %s"

DEFAULT_IFS="${IFS}"
# field separator for cmdline-provided entries, extends %DEFAULT_IFS
CMDLINE_ENTRY_FS="${DEFAULT_IFS}|"

# ----------------------------------------------------------------------------

# @BASH int strfeed_cmd ( str, cmd, *argv )
strfeed_cmd() {
   local str; str="${1?}"; shift; : ${1:?}
   "${@}" <<< "${str}"
}

# wrapper functions:

# @BASH void entry_list_append ( entry_type, key, **ENTRY_LIST! )
entry_list_append() { ENTRY_LIST+=( "${1:?}|${2:?}" ); }

# @BASH int  mp_entry_table_has ( key, **MP_ENTRY_TABLE )
# @BASH void mp_entry_table_set ( key, value, **MP_ENTRY_TABLE! )
mp_entry_table_has() { [ -n "${MP_ENTRY_TABLE[${1:?}]+SET}" ]; }
mp_entry_table_set() { MP_ENTRY_TABLE["${1:?}"]="${2?}"; }

# @BASH int  swap_entry_table_has ( swapdev, **SWAP_ENTRY_TABLE )
# @BASH void swap_entry_table_set ( swapdev, options, **SWAP_ENTRY_TABLE! )
swap_entry_table_has() { [ -n "${SWAP_ENTRY_TABLE[${1:?}]+SET}" ]; }
swap_entry_table_set() { SWAP_ENTRY_TABLE["${1:?}"]="${2?}"; }

# @BASH int entry_table_foreach (
#    func, *args, (**key!), (**entry!),
#    **ENTRY_LIST, **MP_ENTRY_TABLE,
#    **F_FILTER_ENTRY:="true", **F_VALIDATE_ENTRY:="true"
# )
#
#  Calls func(*args,<unpacked entry>,**key,**entry) for each entry
#  in the entry table.
#  Immediately returns on first failure.
#  Optionally validates entries with %F_VALIDATE_ENTRY(**key,**entry) if set.
#  Skips entries for which %F_FILTER_ENTRY(<unpacked entry,**key,**entry)
#  returns false.
#
entry_table_foreach() {
   : ${1:?<func> arg must not be empty.}
   [ ${#ENTRY_LIST[*]} -gt 0 ] || return 0
   local key_type_pair entry entry_type key

   for key_type_pair in "${ENTRY_LIST[@]}"; do
      entry_type="${key_type_pair%%|*}"
      key="${key_type_pair#*|}"

      case "${entry_type}" in
         mp)
            entry="${MP_ENTRY_TABLE[${key:?}]?}"
         ;;
         swap)
            entry="${SWAP_ENTRY_TABLE[${key:?}]?}"
            [ -z "${entry}" ] || entry="${key} none swap ${entry} 0 0"
         ;;
         *)
            die "unknown entry_type ${entry_type}"
         ;;
      esac

      ${F_VALIDATE_ENTRY:-true} || return

      if \
         [ "${F_FILTER_ENTRY:-true}" = "true" ] || \
         ${F_FILTER_ENTRY} ${entry}
      then
         "${@}" ${entry} || return
      fi
   done
}

# void mp_entry_table_update ( key, value ), raises die()
#
#  (Re)adds a (key,value) pair to the entry table and
#  appends the key to the list keys if not already done.
#
mp_entry_table_update() {
   # adding %key to the key list before adding the entry is not super-safe
   ## (COULDFIX: append key after mp_entry_table_set())
   mp_entry_table_has "${1:?}" || entry_list_append mp "${1}" || die
   mp_entry_table_set "${@}"
}

# void swap_entry_table_update ( swapdev, options ), raises die()
#
#  (Re)adds a (swapdev,options) pair to the swap entry table and
#  appends the key to the list keys if not already done.
#
swap_entry_table_update() {
   swap_entry_table_has "${1:?}" || entry_list_append swap "${1}" || die
   swap_entry_table_set "${@}"
}

# @BASH revsort_dirlist ( *dirpath )
revsort_dirlist() {
   sort -d -r <( for w; do [ -z "${w}" ] || printf "%s\n" "${w}"; done )
}

# @BASH makedirs_bakscript_add_rmdir ( dirpath )
makedirs_bakscript_add_rmdir() {
   MAKEDIRS_BACKUP_RMDIR["${1:?}"]=
}

# @BASH makedirs_bakscript_add_symlink ( link_name, link_target )
makedirs_bakscript_add_symlink() {
   [ -z "${MAKEDIRS_BACKUP_SYMLINK[${1:?}]+SET}" ] || \
      die "${1} already in MAKEDIRS_BACKUP_SYMLINK"

   MAKEDIRS_BACKUP_SYMLINK["${1:?}"]="${2:?}"
}

# @BASH generate_makedirs_bakscript()
generate_makedirs_bakscript() {
   local key

   print_line '#!/bin/sh'
   print_line 'set -ufe'
   print_line "DEFAULT_TARGET_DIR=\"${TARGET_DIR}\""
   print_line 'TARGET_DIR="${1:-${DEFAULT_TARGET_DIR}}"'
   print_line '_D="${TARGET_DIR%/}/"'
   print_line 'V_OPT="-v"'
   print_line 'RMDIR_OPTS="--ignore-fail-on-non-empty ${V_OPT}"'
   print_line 'DOSYM_OPTS="${V_OPT}"'
   print_line '# ---'
   print_line 'RMDIR () { rmdir ${RMDIR_OPTS} -- "${_D}${1#/}"; }'
   print_line 'DOSYM () { ln -s ${DOSYM_OPTS} -- "${1}" "${_D}${2#/}"; }'
   print_line '# ---'

   if [ ${#MAKEDIRS_BACKUP_RMDIR[*]} -gt 0 ]; then
      print_line ''
      print_line '# remove directories'

      while read -r key; do
         printf "RMDIR %s\n" "\"${key}\""
      done < <( revsort_dirlist "${!MAKEDIRS_BACKUP_RMDIR[@]}" )
   fi

   if [ ${#MAKEDIRS_BACKUP_SYMLINK[*]} -gt 0 ]; then
      print_line ''
      print_line '# restore symlinks'

      while read -r key; do
         printf "DOSYM %s %s\n" \
            "\"${MAKEDIRS_BACKUP_SYMLINK[${key}]}\"" "\"${key}\""
      done < <( revsort_dirlist "${!MAKEDIRS_BACKUP_SYMLINK[@]}" )
   fi
}

# @noreturn die ( [message:="died."], [exit_code:=2] ), raises exit()
die() {
   printf "%s\n" "${1:+died: }${1:-died.}" 1>&2
   exit ${2:-2}
}

die_usage() { die "${1-}" "${2:-${EX_USAGE:-64}}"; }

# echo might treat args as options, using printf() instead
print_line() { printf "%s\n" "${*}"; }

verbose_printf() { printf "${@}" 1>&2; }

resolve_fspath() {
   v0="$( readlink -m -- "${1}" 2>/dev/null )" && return 0 || true
   v0="$( readlink -f -- "${1}" 2>/dev/null )" && return 0 || true

   case "${1}" in
      /*) v0="${1}" ;;
      *)  v0="${PWD}${1#./}" ;;
   esac
}

# void validate_entry ( **key, **entry ), raises die()
validate_entry() {
   local IFS="${DEFAULT_IFS}" # not necessary
   set -- ${entry?}
   [ $# -eq 6 ] || die \
      "invalid entry: '${key}' -> '${entry}'  (numfields $# != 6)" 50
   # $# == 6 implies that all 6 fields are set and not empty
}

# void entry_makedirs ( fs, mp, ..., **key, **entry )
entry_makedirs() {
   local d did_backup v0 prev
   d="${TARGET_DIR%/}/${2#/}"
   did_backup=
   [ -n "${MAKEDIRS_BAKSCRIPT}" ] || did_backup="null"

   # remove symlinks first
   if [ -h "${d}" ]; then
      if [ -z "${did_backup}" ]; then
         v0="$(readlink -- "${d}")"
         [ -n "${v0}" ] || die "failed to read symlink ${2} in TARGET_DIR"

         makedirs_bakscript_add_rmdir   "${2}"
         makedirs_bakscript_add_symlink "${2}" "${v0}"
         did_backup=symlink
      fi

      rm -- "${d}" || die "makedirs: failed to remove symlink ${d}."
      verbose_printf "makedirs: removed symlink %s\n" "${d}"

   elif [ -d "${d}" ]; then
      # nothing to do here
      return 0

   elif [ -e "${d}" ]; then
      die "makedirs: cannot create dir ${d}: exists, but is not a dir."
   fi

   # also check parent dirs
   #  walk up and create rmdir statements until an existing dir is found
   prev="${2}"; v0="${prev%/*}"
   [ "${v0}" != "${prev}" ] || die "fixme // relpath ${2} in makedirs?"

   if [ -z "${did_backup}" ]; then
      makedirs_bakscript_add_rmdir "${2}"

      while [ -n "${v0}" ]; do
         [ ! -d "${TARGET_DIR%/}/${v0}" ] || break
         [ ! -h "${TARGET_DIR%/}/${v0}" ] || \
            die "makedirs: cannot handle unresolvable symlink: ${v0}"

         makedirs_bakscript_add_rmdir "${v0}"
         prev="${v0}"; v0="${v0%/*}"
         [ "${v0}" != "${prev}" ] || \
            die "fixme // relpath ${2} :: ${v0} in makedirs?"
      done

      did_backup=rmdirs
   fi

   mkdir -p -- "${d}" || die "makedirs: failed to create dir ${d}."
   verbose_printf "makedirs: created directory %s\n" "${d}"
}

# @stdout ~int normpath ( fspath )
#
#  Removes double slashes "/" and trailing slashes from the given filesystem
#  path and writes the result to stdout.
#
normpath() {
   # @COULDFIX: eliminate "./", "../"
   strfeed_cmd "${1:?}" sed -r -e 's,[/]+,/,g' -e 's,(.)[/]$,\1,'
}

# void entry_table_update ( fs, mp, fstype, opts, dump, pass ), raises die()
#
#  Adds an entry to the entry table after determining its type/key.
#
entry_table_update() {
   : ${1:?} ${2:?} ${3:?} ${4:?} ${5:?} ${6:?}
   local key

   case "${3}" in
      swap)
         key="$( normpath "${1}" )"
         swap_entry_table_update "${key:?}" "${4}"
         return 0
      ;;
   esac

   if [ "${2#/}" = "${2}" ]; then
      print_line ">> entry: $*" 1>&2
      die "entry_table_update: unsupported mountpoint '${2}' (relpath?)"
   fi

   key="$( normpath "${2}" )"
   mp_entry_table_update "${key:?}" "${1} ${key} ${3} ${4} ${5} ${6}"
}

# int is_dont_care_value ( value )
is_dont_care_value() {
   case "${1-}" in
      ''|'-') return 0 ;;
   esac
   return 1
}

# @stdout ~int join_mount_options_stdout ( *args )
join_mount_options_stdout() {
   strfeed_cmd "$*" awk '\
   BEGIN {
      # split on whitespace and ","
      RS = "(\\s|[,])+";
      is_first = 1;
   }

   # discard dont-care values (match non-empty values != "-")
   ($0"") && ( $0 != "-" ) {
      # print option, prefix with "," unless it is the first one
      printf( "%s", (is_first ? "" : ",") $0 );
      is_first = 0;
   }

   END { printf("\n"); }'
}

# void join_mount_options ( *args, **v0! )
join_mount_options() { v0="$( join_mount_options_stdout "${@}" )"; }

# get_tmpfs_mode_option ( mode_str, **v0! )
get_tmpfs_mode_option() {
   if is_dont_care_value "${1-}"; then
      v0="mode=1777"
   else
      case "${1-}" in
         rw|ro|mode=*)
            v0="${1}"
         ;;
         *)
            v0="mode=${1:?}"
         ;;
      esac
   fi
}

# int process_entry_line ( *<entry_line> )
#
#  Processes an entry, i.e. adds it to the entry table.
#  Empty lines and comment lines get discarded.
#  Immediately returns non-zero if any line cannot be parsed.
#
process_entry_line() {
   local v0

   case "${1-}" in
      '')
         # $1 empty/not set: line empty or whitespace only, ignore
         true
      ;;
      '#'*)
         # comment line, ignore
         true
      ;;
      '@bind')
         # @bind <from> <to> [<options>]
         [ $# -lt 5 ] && [ -n "${2-}" ] && [ -n "${3-}" ] || return 30

         join_mount_options "bind" "${4-}"

         entry_table_update "${2}" "${3}" "none" "${v0}" "0" "0"
      ;;
      '@tmpfs')
         # @tmpfs <mp> [<mode> [<size> [<options> [<name>]]]]
         [ $# -lt 7 ] && [ -n "${2-}" ] || return 40

         get_tmpfs_mode_option "${3-}"

         if is_dont_care_value "${4-}"; then
            join_mount_options "${v0}" "${5-}"
         else
            join_mount_options "${v0}" "size=${4}" "${5-}"
         fi

         entry_table_update "${6:-tmpfs}" "${2}" "tmpfs" "${v0}" "0" "0"
      ;;
      '@swap')
         # @swap <fs> [<options>]
         [ $# -lt 4 ] && [ -n "${2-}" ] || return 50

         join_mount_options "sw" "${3-}"

         entry_table_update "${2}" "none" "swap" "${v0}" "0" "0"
      ;;
      '@'*)
         # invalid "special" mount entry
         return 5
      ;;
      *)
         # <fs> <mp> <fstype> [<options> [<dump> [<pass>]]]
         if [ $# -lt 7 ] && \
            [ -n "${1-}" ] && [ -n "${2-}" ] && [ -n "${3-}" ]
         then
            entry_table_update \
               "${1}" "${2}" "${3}" "${4:-defaults}" "${5:-0}" "${6:-0}"
         else
            return 20
         fi
      ;;
   esac
}

# int process_cmdline_entry ( line )
#
#  Performs word-splitting on %line and calls process_entry_line(<words>)
#  afterwards.
#
process_cmdline_entry() {
   local IFS="${CMDLINE_ENTRY_FS?}"
   set -- ${1:?}
   IFS="${DEFAULT_IFS}"
   process_entry_line "${@}"
}

# int read_infile ( filepath )
#
#  Reads and processes and fstab-like file.
#
read_infile() {
   local lino line

   lino=0
   while read -r line; do
      lino=$(( ${lino} + 1 ))

      if ! process_entry_line ${line}; then
         1>&2 printf "%s, line %d: cannot parse this line: %s\n" \
            "${1}" "${lino}" "${line}"
         return 2
      fi
   done < "${1:?}"
}

# void main_read_infiles ( *filepath ), raises die()
#
main_read_infiles() {
   while [ $# -gt 0 ]; do
      # test -f <> || test -c <> [...]
      if [ -e "${1}" ] && [ ! -d "${1}" ] ; then
         read_infile "${1}" || die "failed to read ${1}"

      elif [ -z "${ignore_missing}" ]; then
         die "no such file: ${1}"
      fi

      shift
   done
}

# void main_parse_args ( *argv ), raises die()
#
main_parse_args() {
   local v0 ignore_missing=

   while [ $# -gt 0 ]; do
      case "${1}" in
         '')
            # ignore
            shift
         ;;
         '-d'|'--makedirs')
            [ -n "${2-}" ] || die_usage \
               "missing ${2+non-empty }<dir> arg after ${1} option"

            resolve_fspath "${2}" || die
            [ -d "${v0}" ] || die_usage "${1}: not a dir: ${2} (${v0})"

            [ "${v0}" != "/" ] || die "TARGET_DIR must not be ${v0}"

            TARGET_DIR="${v0}"
            shift 2
         ;;
         '-E'|'--entry')
            [ -n "${2-}" ] || die_usage \
               "missing ${2+non-empty }<entry> arg after ${1} option"
            process_cmdline_entry "${2}" || \
               die "failed to parse cmdline entry: ${2}"

            shift 2
         ;;
         '-F'|'--makedirs-backup')
            [ -n "${2-}" ] || \
               die_usage "missing ${2+non-empty }<file> arg after ${1} option"

            MAKEDIRS_BAKSCRIPT="${2}"
            shift 2
         ;;
         '-h'|'--help')
            mkfstab_print_help
            exit 0
         ;;
         '-O'|'--outfile')
            [ -n "${2-}" ] || die_usage \
               "missing ${2+non-empty }<file> arg after ${1} option"

            FSTAB_OUTFILE="${2}"
            shift 2
         ;;
         '-s'|'--ignore-missing')
            ignore_missing=Y

            shift
         ;;
         -*)
            die_usage "unknown option: ${1}"
         ;;
         --)
            shift
            main_read_infiles "${@}"
            set --
         ;;
         *)
            main_read_infiles "${1}"
            shift
         ;;
      esac
   done
}

# int main_prepare_outfile ( filepath, desc, **v0! ), raises die()
#
main_prepare_outfile() {
   : ${2:?}
   v0=
   [ -n "${1}" ] || return 1

   if ! resolve_fspath "${1}"; then
      die
   elif [ -d "${v0:?}" ]; then
      die "${2} must not be a dir: ${1}"
   elif ! mkdir -p -- "${v0%/*}"; then
      die "failed to create dir for ${2}: ${v0%/*}"
   elif ! : > "${v0}"; then
      die "cannot write to ${2}: ${v0}"
   fi
}

filter_swap_entry() {
   [ "${3:?}" != "swap" ]
}

# void main ( *argv ), raises die()
#
main() {
   local v0
   F_VALIDATE_ENTRY=validate_entry
   unset -v F_FILTER_ENTRY
   unset -v TARGET_DIR
   unset -v FSTAB_OUTFILE
   unset -v MAKEDIRS_BAKSCRIPT

   main_parse_args "${@}" || die

   [ "${FSTAB_OUTFILE:--}" != "-" ] || FSTAB_OUTFILE=
   if main_prepare_outfile "${FSTAB_OUTFILE}" "fstab outfile"; then
      FSTAB_OUTFILE="${v0}"
      exec 3>>"${v0}" || die
   else
      FSTAB_OUTFILE=
      exec 3>&1 || die
   fi

   if [ -n "${MAKEDIRS_BAKSCRIPT=}" ]; then
      [ -n "${TARGET_DIR-}" ] || \
         die_usage "makedirs bakscript needs --makedirs"

      main_prepare_outfile "${MAKEDIRS_BAKSCRIPT}" "makedirs bakscript" || die
      MAKEDIRS_BAKSCRIPT="${v0}"
   fi

   # create directories before spitting out entries
   if [ -n "${TARGET_DIR-}" ]; then
      F_FILTER_ENTRY=filter_swap_entry

      entry_table_foreach entry_makedirs || die "failed to create directories!"
      # no need to validate entries again
      F_VALIDATE_ENTRY=true
      F_FILTER_ENTRY=

      if [ -n "${MAKEDIRS_BAKSCRIPT}" ]; then
         generate_makedirs_bakscript >> "${MAKEDIRS_BAKSCRIPT}" || \
            die "failed to generate makedirs fixup script."

         # check/chmod script if it has been written to a file
         if [ -f "${MAKEDIRS_BAKSCRIPT}" ]; then
            sh -n "${MAKEDIRS_BAKSCRIPT}" || \
               die "makedirs fixup script is broken!"
            chmod +x -- "${MAKEDIRS_BAKSCRIPT}" || die "chmod"
         fi
      fi
   fi

   # write fstab
   {
      print_line "# /etc/fstab: static file system information."
      print_line "#"

      printf "${HEADER_ENTRY_FMT}\n" \
         "# <file system>" "<mount pt>" "<type>" "<options>" "<dump>" "<pass>"

      entry_table_foreach printf "${ENTRY_FMT}\n"
   } >&3 || die "failed to write fstab outfile"

   # close fd
   exec 3>&- || die
}


# ----------------------------------------------------------------------------
main "${@}"
