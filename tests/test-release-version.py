#!/usr/bin/env python3
import re, subprocess, tempfile, shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/"repo"; shutil.copytree(root,p,ignore=shutil.ignore_patterns(".git","build","third_party"))
 script=p/"scripts/derive-release-version.sh"
 major,minor,patch=map(int,(p/"VERSION").read_text().strip().split("."))
 assert subprocess.check_output([script,"1"],text=True).strip()==f"{major}.{minor}.{patch+1}"
 assert subprocess.check_output([script,"42"],text=True).strip()==f"{major}.{minor}.{patch+42}"
 stamped=f"{major}.{minor}.{patch+42}"
 subprocess.check_call([p/"scripts/stamp-version.sh",stamped])
 assert (p/"VERSION").read_text().strip()==stamped
 assert subprocess.check_output([script,"--diagnostic"],text=True).strip()==stamped
 print("PASS lmproxy run-derived release version")
