#!/usr/bin/env python3
"""Read-only: list bibkeys added/removed/changed between two corpus git revisions.

Usage: corpus_diff_keys.py CORPUS_DIR OLD_REV NEW_REV
"""
import csv
import io
import subprocess
import sys


def load(corpus, rev):
    out = {}
    files = subprocess.check_output(
        ["git", "-C", corpus, "ls-tree", "-r", "--name-only", rev, "data/bibitem/"], text=True
    ).split()
    for f in files:
        text = subprocess.check_output(["git", "-C", corpus, "show", f"{rev}:{f}"], text=True)
        for row in csv.DictReader(io.StringIO(text)):
            out[row["bibkey"]] = row
    return out


corpus, old_rev, new_rev = sys.argv[1:4]
old, new = load(corpus, old_rev), load(corpus, new_rev)
added = sorted(set(new) - set(old))
removed = sorted(set(old) - set(new))
changed = sorted(k for k in set(old) & set(new) if old[k] != new[k])
print(f"old={len(old)} new={len(new)} added={len(added)} removed={len(removed)} changed={len(changed)}")
print("ADDED", *added[:30])
print("REMOVED", *removed[:30])
print("CHANGED", *changed[:30])
