#!/bin/sh

# some distros use /etc/bash.bashrc, others use /etc/bash/bashrc
if [ -f "${S}/bash/bashrc" ] && [ ! -f "${S}/bash.bashrc" ]; then
   dst_halfway_safe_symlink bash/bashrc bash.bashrc
fi

if [ -f "${S}/locale.conf" ]; then
   target_dodir "${D}/env.d"
   target_rmfile "${D}/env.d/02locale"
   autodie ln -s -- ../locale.conf "${D}/env.d/02locale"
fi
