#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
#  A server-side ssh command script that allows two machines to establish
#  a ssh connection via a third machine [running this script].
#
#
# Consider the following situation:
#
#   * [user of] machine NEEDHELP occasionally needs support and
#     - the task(s) can be done remotely via ssh
#     - an sshd server is running on machine NEEDHELP,
#       but A is behind a router|firewall and port forwarding is impractical
#     - NEEDHELP might have a dynamical IP addr (and no dyndns)
#
#   * user of machine SUPPORTER (or users of machines SUPPORTER_{0..N})
#     is knowledgeable to provide support, but may also be behind
#     a router|firewall and/or have a dynamic IP addr
#
#   * there's a server M running somewhere that be accessed from both
#     NEEDHELP and SUPPORTER via ssh
#
# which basically boils down to:
#
#   * NEEDHELP cannot connect to SUPPORTER and vice versa
#
#   * NEEDHELP can connect to M and SUPPORTER can connect to M
#
# => SUPPORTER can establish an indirect connection to NEEDHELP via M
#    iff NEEDHELP is already connected to M(!)
#
# With this solution, both NEEDHELP and SUPPORTER must *deliberately*
# initiate a connection, i.e. keep control over when to accept connections
# without having to start/stop sshd etc.
#
# * NEEDHELP  must have access to M (user account)
# * SUPPORTER must have access to *both* M and NEEDHELP
#
# On the server side (M), you need to:
#
#   * create a user account, e.g. "revssh"
#
#   * add ssh keys from NEEDHELP and SUPPORTER to ~revssh/.ssh/authorized_keys:
#
#        command="/path/to/revssh-server.py" ssh-rsa <pubkey>
#
#   * (optionally) create a "host config" file to get the "getscript"
#     command working, either ~revssh/.config/revssh or /etc/revssh.conf,
#     with the following lines (replace w/ appropiate values):
#
#        sshd_host = example.org
#        sshd_port = 22
#        sshd_user = revssh
#
# $$$DOCME$$$
#

from __future__ import absolute_import
from __future__ import unicode_literals, division, generators
from __future__ import print_function, nested_scopes, with_statement

import argparse
import os
import shlex
import string
import sys
import time

def get_arg_parser ( prog ):
   parser         = argparse.ArgumentParser ( prog=prog, add_help=False )
   sparsers       = parser.add_subparsers (
      title='commands', dest='command',
   )
   subparser      = sparsers.add_parser

   parser_help      = subparser ( 'help',      help='print help' )
   parser_open      = subparser ( 'open',      help='open a new tunnel' )
   parser_connect   = subparser ( 'connect',   help='connect to a tunnel' )
   parser_ssh       = subparser ( 'ssh',       help='run ssh',
      add_help=False, prefix_chars=' '
   )
   parser_getscript = subparser ( 'getscript', help='get the client script' )

   # "open"
   parser_open.add_argument (
      '-t', '--timeout', dest='open_timeout',
      default=argparse.SUPPRESS, metavar='<seconds>', type=int,
      help='connection timeout'
   )

   parser_open.add_argument (
      '-p', '--rport', dest='open_remote_port',
      default=argparse.SUPPRESS, metavar='<remote port>', type=int,
      help='tunnel remote port'
   )

   # "connect"
   parser_connect.add_argument (
      'connect_port', metavar='<port>',  type=int,
      help='port to connect to'
   )

   parser_connect.add_argument (
      'connect_user', metavar='<user>', type=str,
      help='user name'
   )

   # "ssh"
   parser_ssh.add_argument (
      'ssh_args', metavar='<arg>', nargs=argparse.REMAINDER
   )

   # "getscript"
   parser_getscript.add_argument (
      '-L', '--variant', dest='getscript_variant', metavar='<variant>',
      choices=[ 'sh', 'perl', 'python' ], default='sh',
      help='script variant (%(choices)s)'
   )

   parser_getscript.add_argument (
      '-r', '--rport', dest='getscript_remote_port',
      default=57001, metavar='<remote port>', type=int,
      help='tunnel remote port [%(default)s]'
   )

   parser_getscript.add_argument (
      '-p', '--port', dest='getscript_local_port',
      default=22, metavar='<local port>', type=int,
      help='local port [%(default)s]'
   )

   parser_getscript.add_argument (
      '-o', '--ssh-opt', dest='getscript_ssh_options', metavar='<option>',
      default=[
         'ExitOnForwardFailure=yes',
         'UserKnownHostsFile=/dev/null', 'StrictHostKeyChecking=no'
      ],
      action='append',
      help='ssh options (e.g. ExitOnForwardFailure)'
   )

   parser_getscript.add_argument (
      '--ssh-prog', dest='getscript_ssh_program', metavar='<prog>',
      default='ssh', help='ssh program name or path [%(default)s]'
   )

   return parser
# --- end of get_arg_parser (...) ---


class CommandDispatcher ( object ):
   # pack commands into an object so we don't have to
   # import __main__ && getattr ( __main__, method )

   SSH_PROG = '/usr/bin/ssh'
   SSH_ARGV = [
      SSH_PROG,
      '-o', 'UserKnownHostsFile=/dev/null',
      '-o', 'StrictHostKeyChecking=no'
   ]
   COMMANDS = frozenset ({ 'help', 'open', 'connect', 'ssh', 'getscript' })

   def __init__ ( self ):
      super ( CommandDispatcher, self ).__init__()
      self.STR_FORMATTER = string.Formatter()
      self.str_vformat   = self.STR_FORMATTER.vformat

   def run_command ( self, command, host_config, config ):
      if not command: raise ValueError()

      method_name = 'run_command_' + command

      # "raise <> from None" needs py3 or ugly workarounds
      method = getattr ( self, method_name, None )
      if method is None:
         raise NotImplementedError ( command )

      return method ( host_config, config )
   # --- end of run_command (...) ---

   def run_command_ssh ( self, host_config, config ):
      try:
         os.execv ( self.SSH_PROG, self.SSH_ARGV + list(config.ssh_args) )
      except OSError:
         return os.EX_OSERR

   def run_command_help ( self, host_config, config ):
      return True

   def run_command_connect ( self, host_config, config ):
      argv = self.SSH_ARGV + [
         'localhost', '-p', config.connect_port, '-l', config.connect_user
      ]
      try:
         os.execv ( self.SSH_PROG, argv )
      except OSError:
         return os.EX_OSERR

   def run_command_open ( self, host_config, config ):
      outstream       = sys.stdout
      write_outstream = outstream.write

      timeout = getattr ( config, 'open_timeout', None )

      write_outstream ( '\n*** revssh tunnel has been opened ***\n\n' )

      if not timeout or timeout < 1:
         write_outstream ( 'timeout = <none>\n' )
      else:
         write_outstream ( 'timeout = {:d} seconds\n'.format ( timeout ) )

      if getattr ( config, 'open_remote_port', None ):
         # 0 is not a valid port anyway
         write_outstream (
            'port    = {:d}\n'.format ( config.open_remote_port )
         )

      write_outstream (
         '\nPress ^C or close this window to abort at any time.\n'
      )

      outstream.flush()

      try:
         if not timeout or timeout < 1:
            while True: time.sleep ( 120 )
         else:
            time.sleep ( timeout )
      except KeyboardInterrupt:
         return True
   # --- end of run_command_open (...) ---

   def run_command_getscript ( self, host_config, config ):
      outstream_write = sys.stdout.write
      fvars = {
         k : getattr ( config, 'getscript_' + k ) for k in [
            'variant', 'remote_port', 'local_port',
            'ssh_options', 'ssh_program'
         ]
      }

      fvars ['ssh_options_str'] = ' '.join (
         [ '-o ' + k for k in fvars ['ssh_options'] ]
      )

      for k in [ 'sshd_host', 'sshd_user' ]:
         if k not in host_config or host_config [k] is None:
            sys.stderr.write (
               'Cannot create script - host config is incomplete.\n'
            )
            return False
         else:
            fvars ['host_' + k] = host_config [k]
      # -- end for

      fvars ['host_sshd_port'] = host_config.get('sshd_port') or '22'

      if config.getscript_variant == 'sh':
         outstream_write (
            self.str_vformat (
               (
                  '#!/bin/sh\n'
                  '#  This script should be run on the client side.\n'
                  '#  (machine that wants to get a port tunnelled)\n'
                  '#\n'
                  '#  Usage: open-revssh-tunnel '
                     '[<remote port>[ <local port>[ <timeout>]]]\n'
                  '#\n'
                  '# This script has been automatically generated.\n'
                  '#\n'
                  'set -f\n'
                  '\n'
                  '# local config\n'
                  'DEFAULT_LOCAL_PORT="{local_port}"\n'
                  'DEFAULT_REMOTE_PORT="{remote_port}"\n'
                  'X_SSH="{ssh_program}"\n'
                  'SSH_OPTS="{ssh_options_str}"\n'
                  '\n'
                  '# remote server config\n'
                  'REVSSH_REMOTE_SSHD_HOST="{host_sshd_host}"\n'
                  'REVSSH_REMOTE_SSHD_PORT="{host_sshd_port}"\n'
                  'REVSSH_REMOTE_SSHD_USER="{host_sshd_user}"\n'
                  '\n'
                  '# cmdline args\n'
                  'remote_port="${{1:-${{DEFAULT_REMOTE_PORT}}}}"\n'
                  'local_port="${{2:-${{DEFAULT_LOCAL_PORT}}}}"\n'
                  'timeout="${{3:--1}}"\n'
                  '\n'
                  '\n'
                  '# posix sh does not set UID/HOME\n'
                  'id_uid="$(id -u)"; : ${{id_uid:?}}\n'
                  'home="$(getent passwd "${{id_uid}}" | cut -d \: -f 6)"\n'
                  ': ${{home:?}}\n'
                  '\n'
                  'keyfile="${{home}}/.ssh/revssh_key"\n'
                  'if ! [ -f "${{keyfile}}" ]; then\n'
                  '   printf \'%s\\n\' \'No keyfile found!\'\n'
                  'fi\n'
                  '\n'
                  'set -- \\\n'
                  '   "${{X_SSH}}" ${{SSH_OPTS}} \\\n'
                  '   -R "${{remote_port}}:localhost:${{local_port}}" \\\n'
                  '   -i "${{keyfile}}" \\\n'
                  '   "${{REVSSH_REMOTE_SSHD_HOST}}"\n'
                  '\n'
                  '[ -z "${{REVSSH_REMOTE_SSHD_USER}}" ] || '
                     'set -- "${{@}}" -l "${{REVSSH_REMOTE_SSHD_USER}}"\n'
                  '[ -z "${{REVSSH_REMOTE_SSHD_PORT}}" ] || '
                     'set -- "${{@}}" -p "${{REVSSH_REMOTE_SSHD_PORT}}"\n'
                  '\n'
                  'set -- "${{@}}" \\\n'
                  '   open --timeout "${{timeout}}" --rport "${{remote_port}}"\n'
                  '\n'
                  'exec "${{@}}"\n'
               ),
               (),
               fvars
            )
         )
      else:
         raise NotImplementedError ( 'getscript', config.getscript_variant )
# --- end of CommandDispatcher ---

def get_host_config():
   def iter_candidates():
      if os.environ.get('HOME', None):
         yield os.path.join ( os.environ['HOME'], '.config', 'revssh' )
      yield '/etc/revssh.conf'
   # ---

   cfg = {}
   for cand in filter ( os.path.isfile, iter_candidates() ):
      with open ( cand, 'rt' ) as fh:
         for line in fh:
            sline = line.strip()
            if sline and sline[0] != '#':
               k, delim, v = sline.partition('=')
               if delim:
                  cfg [k.rstrip()] = v.lstrip()
      # -- end with
      break
   # --

   return cfg
# --- end of get_host_config (...) ---

def main ( prog, argv ):
   command_dispatcher = CommandDispatcher()

   if not argv or not argv[0]:
      sys.stderr.write ( 'No command specified!\n' )
      return False

   elif argv[0] not in command_dispatcher.COMMANDS:
      ## log that
      sys.stderr.write (
         'You\'re not allowed to execute arbitrary commands on this server.\n'
         '(This incident has been logged.)\n'
      )
      return False

   parser      = get_arg_parser ( prog )
   config      = parser.parse_args ( argv ) ## parse_known_args(), exit if unknown
   host_config = get_host_config()

   if not config.command:
      sys.stderr.write ( 'unknown command: {!r}\n'.format ( config.command ) )
      return os.EX_SOFTWARE

   elif config.command == 'help':
      parser.print_help()
      return True

   else:
      return command_dispatcher.run_command (
         config.command, host_config, config
      )
# --- end of main (...) ---

if __name__ == '__main__':
   try:
      arg_str = os.environ.get ( 'SSH_ORIGINAL_COMMAND', '' )

      excode = main ( os.path.basename(sys.argv[0]), shlex.split ( arg_str ) )
   except KeyboardInterrupt:
      excode = os.EX_OK ^ 130
   except:
      # do not show exceptions.
      excode = os.EX_OK ^ 222
   else:
      if excode is None or excode is True:
         excode = os.EX_OK
      elif excode is False:
         excode = os.EX_OK ^ 1

   sys.exit ( excode )
# -- end if
