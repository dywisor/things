#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# This file is part of @@PROG_NAME@@.
#

from __future__ import absolute_import
from __future__ import unicode_literals, division, generators
from __future__ import print_function, nested_scopes, with_statement

import os
import sys

def main ( prog, argv ):
   pass
# --- end of main (...) ---

if __name__ == '__main__':
   try:
      excode = main ( sys.argv[0], sys.argv[1:] )
   except KeyboardInterrupt:
      excode = os.EX_OK ^ 130
   else:
      if excode is None or excode is True:
         excode = os.EX_OK
      elif excode is False:
         excode = os.EX_OK ^ 1
   # -- end try

   sys.exit ( excode )
