#!/usr/bin/env python
import os
import sys

if __name__ == '__main__':
   if len(sys.argv) < 2 or not sys.argv[1]:
      sys.exit(os.EX_USAGE)

   applet = getattr ( os.path, sys.argv[1], None )
   if applet is None:
      applet = getattr ( os, sys.argv[1], None )

   if applet is None or not hasattr(applet, '__call__'):
      sys.stderr.write('applet not found: {}\n'.format(sys.argv[1]))
      sys.exit(os.EX_OK^1)

   try:
      rets = applet(*(sys.argv[2:]))

   except TypeError:
      raise
      sys.exit(os.EX_USAGE)

   except OSError:
      sys.exit(os.EX_OK^1)

   if rets is True:
      sys.exit(os.EX_OK)
   elif rets is False:
      sys.exit(os.EX_OK^1)
   elif rets is not None:
      print(rets)

   sys.exit(os.EX_OK)
