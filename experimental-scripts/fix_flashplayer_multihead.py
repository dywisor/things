#!/usr/bin/python
# -*- coding: utf-8 -*-
# Copyright (C) 2012 André Erdmann <dywi@mailerd.de>
# Distributed under the terms of the GNU General Public License;
# either version 2 of the License, or (at your option) any later version.
#
# ----------------------------------------------------------------------------
# Changelog:
#
# * 2012-12-20, Andre Erdmann:
#  - script created
# ----------------------------------------------------------------------------

"""
Edits a (binary) libflashplayer.so file so that user interaction in
multihead setups does not disturb the fullscreen mode in flash videos.

Abstract usage:
   fix_flashplayer_multihead.py <in_file> <out_file>

   where <in_file> has to exist (as file) and <out_file> must not.

Example usage:
   fix_flashplayer_multihead.py libflashplayer.so.orig libflashplayer.so.fixed

Meant for direct execution (stand-alone script).
"""

import os
import sys
import mmap
import shutil

# (python3:) dont forget the 'b' prefix (or specify encoding)
MAGIC            = b'_NET_ACTIVE_WINDOW'
MAGIC_REPLACE_BY = b'__ET_ACTIVE_WINDOW'

def die ( message=None, code=None ):
   """Script exit function. Writes message to stderr if specified, and
   exits afterwards with the given exit code.

   arguments:
   * message -- message that should be written to stderr (if it
                evaluates to true)
   * code    -- exit code for sys.exit
                Defaults to 1 if os.EX_OK is 0 else 0.
   """
   if message:
      sys.stderr.write ( message )
      sys.stderr.write ( '\n' )

   sys.exit (
      ( 1 if os.EX_OK == 0 else 0 ) if code is None else code
   )
# --- end of die (...) ---

def dodir ( dirpath ):
   """Ensures that a directory exists. Creates it if necessary.

   arguments:
   * dirpath -- directory path
   """

   if sys.version_info.major > 2:
      os.makedirs ( dirpath, exist_ok=True )
   elif not os.path.isdir ( dirpath ):
      os.makedirs ( dirpath )
# --- end of dodir (...) ---

def fix_libflashplayer ( filepath ):
   """Fixes the given file by replacing any occurence of MAGIC
   by MAGIC_REPLACE_BY.
   Returns the number of fixed occurences.

   arguments:
   * filepath -- file to fix
   """
   fixcount = 0
   with open ( filepath, 'r+b' ) as FH:
      # operate on a mmap-ed version of FH and flush changes when done
      # solution: while MAGIC in mapped: replace MAGIC, MAGIC_REPLACE_BY

      mapped = mmap.mmap ( FH.fileno(), 0 )
      pos    = mapped.find ( MAGIC, 0 )
      while pos >= 0:
         print ( "fixing position {}".format ( pos ) )
         mapped.seek ( pos )

         fixcount += 1

         mapped.write ( MAGIC_REPLACE_BY )

         pos = mapped.find ( MAGIC, pos + 1 )

      mapped.flush()
      mapped.close()
   # --- end with;

   return fixcount
# --- end of fix_libflashplayer (...) ---

def main():
   """main method"""

   def die_usage():
      """Prints the usage message and dies afterwards."""
      die (
         'Usage: {} <input> <output>'.format (
            os.path.basename ( sys.argv [0] )
         ),
         os.EX_USAGE
      )
   # --- end of print_usage (...) ---

   def get_arg_or_die ( argnum ):
      """Returns sys.argv[argnum] if possible, else calls die_usage().

      arguments:
      * argnum --
      """
      if argnum < len ( sys.argv ):
         return sys.argv [argnum]
      else:
         die_usage()
   # --- end of get_arg_or_die (...) ---

   in_file  = get_arg_or_die ( 1 )
   out_file = get_arg_or_die ( 2 )

   if in_file and out_file:
      in_file  = os.path.abspath ( os.path.expanduser ( in_file  ) )
      out_file = os.path.abspath ( os.path.expanduser ( out_file ) )

      if not os.path.isfile ( in_file ):
         die ( 'input file {!r} does not exist'.format ( in_file ) )
      elif os.path.exists ( out_file ):
         die ( 'output file {!r} already exists'.format ( out_file ) )
      else:
         dodir ( os.path.dirname ( out_file ) )

         shutil.copyfile ( in_file, out_file )
         try:
            try:
               shutil.copystat ( in_file, out_file )
            except ( OSError, IOError ):
               pass

            fix_libflashplayer ( out_file )

         except ( Exception, KeyboardInterrupt ) as err:
            # or use tmpfile and move it to out_file just before exiting
            os.unlink ( out_file )
            raise
         # --- end try;
      # --- end if;

# --- end of main (...) ---

if __name__ == '__main__':
   main()

