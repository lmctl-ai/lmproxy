#!/usr/bin/env python3
"""Offline example recipes invoke their native program exactly once."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
for path in sorted((root/'examples').glob('*.lms')):
 text=path.read_text(encoding='utf-8')
 line=next(line for line in text.splitlines() if line.startswith('# Run:'))
 assert '--lmcode' not in line,(path,line)
 assert text.count('run_lmcode(')==1,path
print('PASS each documented example invokes the native program once')
