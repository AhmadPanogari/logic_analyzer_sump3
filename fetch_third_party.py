#!/usr/bin/env python3
"""
fetch_third_party.py : get the BlackMesaLabs sources into third_party/.

  python fetch_third_party.py

third_party/sump3 and third_party/MesaBusProtocol are git submodules. A
"Download ZIP" from GitHub does not contain them, so the folders are empty
and vivado/build.tcl stops with "third_party submodules missing".

  * In a git clone this runs: git submodule update --init --recursive
  * Otherwise ( ZIP download, no git ) it downloads the pinned commits from
    GitHub as ZIP archives and unpacks them. Only the Python standard library
    is needed.

Keep PINNED in sync with the submodule commits ( git submodule status ).
"""

import io
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))

PINNED = [
  # ( path, GitHub repo, commit )
  ("third_party/sump3",           "blackmesalabs/sump3",
   "3cd2065eb4ecbfbf18754f53f7be2469c27ad88f"),
  ("third_party/MesaBusProtocol", "blackmesalabs/MesaBusProtocol",
   "d62f267abc4351ca6b5c0d004afc2551e6d95c49"),
]

# One file per submodule that the build needs, to tell if it is populated
CHECK = {
  "third_party/sump3":           "verilog/sump3_core.v",
  "third_party/MesaBusProtocol": "verilog/ft232_xface.v",
}


def populated(path):
  return os.path.isfile(os.path.join(ROOT, path, CHECK[path]))


def try_git():
  if not os.path.isdir(os.path.join(ROOT, ".git")) or shutil.which("git") is None:
    return False
  print("git clone detected: git submodule update --init --recursive")
  rc = subprocess.call(["git", "submodule", "update", "--init", "--recursive"], cwd=ROOT)
  return rc == 0 and all(populated(p) for p, _, _ in PINNED)


def download(path, repo, sha):
  url = "https://github.com/%s/archive/%s.zip" % (repo, sha)
  print("Downloading %s" % url)
  with urllib.request.urlopen(url, timeout=120) as r:
    data = r.read()
  dest = os.path.join(ROOT, path)
  if os.path.isdir(dest):
    shutil.rmtree(dest)
  os.makedirs(dest)
  with zipfile.ZipFile(io.BytesIO(data)) as zf:
    for info in zf.infolist():
      # Strip the "<repo>-<sha>/" top folder of the GitHub archive
      parts = info.filename.split("/", 1)
      if len(parts) < 2 or not parts[1]:
        continue
      target = os.path.normpath(os.path.join(dest, parts[1]))
      if not target.startswith(os.path.normpath(dest) + os.sep):
        continue   # never write outside dest
      if info.is_dir():
        os.makedirs(target, exist_ok=True)
      else:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with zf.open(info) as src, open(target, "wb") as dst:
          shutil.copyfileobj(src, dst)
  print("  -> %s" % dest)


def main():
  if all(populated(p) for p, _, _ in PINNED):
    print("third_party/ already complete.")
    return 0
  if try_git():
    print("Done.")
    return 0
  for path, repo, sha in PINNED:
    if not populated(path):
      download(path, repo, sha)
  missing = [p for p, _, _ in PINNED if not populated(p)]
  if missing:
    print("ERROR: still missing: %s" % ", ".join(missing))
    return 1
  print("Done. Now run the Vivado build again.")
  return 0


if __name__ == "__main__":
  sys.exit(main())
