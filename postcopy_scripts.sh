#!/bin/sh

# py symlinks
if [ -n "${ROOT}" ]; then
   set --
   for py in \
      "${ROOT%/}/usr/bin/python"[0-9] \
      "${ROOT%/}/usr/bin/python"[0-9].[0-9]
   do
      ! test_fs_lexists "${py}" || set -- "${@}" "${py##*/python}"
   done

   for pyver in "${@}"; do
      dst_halfway_safe_symlink py "py${pyver}"
   done

   set --
fi

# scp-unsafe -> ssh-unsafe
dst_halfway_safe_symlink ssh-unsafe scp-unsafe

# get-tc, get-tc-x -> get-toolchain.sh
dst_halfway_safe_symlink get-toolchain.sh get-tc
dst_halfway_safe_symlink get-toolchain.sh get-tc-x
