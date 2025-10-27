#!/usr/bin/env python3
"""
Shim that ensures toolshed.files.prefunc exists, then runs bwameth.py.

Usage:
  ./bwameth-wrapper.py <bwameth-args...>

Place this in ~/bin (or another dir in your PATH), chmod +x it, and call it in place of
`python /usr/local/bin/bwameth.py` or put it in your workflow (e.g. set bwameth_path to this).
"""
import importlib
import os
import runpy
import sys

# Try to ensure toolshed.files.prefunc exists (no-op if already present).
try:
    tsfiles = importlib.import_module("toolshed.files")
    if not hasattr(tsfiles, "prefunc"):
        def prefunc():
            # typical preexec intent: put the child into its own process group
            try:
                os.setpgrp()
            except Exception:
                # best effort, do not fail if we cannot setpgrp
                pass
        setattr(tsfiles, "prefunc", prefunc)
except Exception:
    # If toolshed isn't importable, we don't try to fix it here.
    # Let bwameth raise an ImportError later; log a hint for diagnostics.
    pass

# Locate the bwameth.py script to execute.
bw_path = "/usr/local/bin/bwameth.py"
if not os.path.exists(bw_path):
    # fallback: search PATH for bwameth.py
    for p in os.environ.get("PATH", "").split(os.pathsep):
        cand = os.path.join(p, "bwameth.py")
        if os.path.exists(cand):
            bw_path = cand
            break

if not os.path.exists(bw_path):
    sys.stderr.write("Error: cannot find bwameth.py in /usr/local/bin or PATH\n")
    sys.exit(2)

# Execute bwameth.py as if it was run directly with the same argv
# Preserve sys.argv (script will see correct arguments)
sys.argv[0] = bw_path
# sys.argv[1:] already contain passed args
runpy.run_path(bw_path, run_name="__main__")
