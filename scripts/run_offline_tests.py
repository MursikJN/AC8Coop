"""Run repository fixtures; never execute the game or establish a Steam session.

Windows restricted tokens cannot reopen CPython's mode-0700 temporary folders.
Use ordinary inherited workspace ACLs for test scratch only, not user data.
"""
from pathlib import Path
import os
import tempfile
import unittest
import sys

ROOT=Path(__file__).resolve().parents[1]
SCRATCH=ROOT/'build/offline-test-scratch'

def main():
 sys.path.insert(0,str(ROOT))
 SCRATCH.mkdir(parents=True,exist_ok=True);tempfile.tempdir=str(SCRATCH)
 original=os.mkdir
 def fixture_mkdir(path,mode=0o777,*,dir_fd=None):
  try:owned=Path(path).resolve().is_relative_to(SCRATCH)
  except (TypeError,ValueError):owned=False
  return original(path,0o777 if os.name=='nt'and owned and mode==0o700 else mode,dir_fd=dir_fd)
 os.mkdir=fixture_mkdir
 try:
  suite=unittest.defaultTestLoader.discover(str(ROOT/'tests'))
  return 0 if unittest.TextTestRunner(verbosity=1).run(suite).wasSuccessful()else 1
 finally:os.mkdir=original

if __name__=='__main__':raise SystemExit(main())
