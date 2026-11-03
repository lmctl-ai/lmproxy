#!/usr/bin/env python3
"""Offline example recipes invoke their native program exactly once."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
for path in sorted((root/'examples').glob('*.lms')):
 line=next(line for line in path.read_text().splitlines() if line.startswith('# Run:'))
 assert line.count('&& lmproxy --lmcode ')==1,(path,line)
print('PASS each documented example invokes the native program once')
