### Note: legacy bwa-meth (bwameth.py) dependency — toolshed

bwameth.py (the bwa-meth wrapper used by these scripts) is an older tool that depends on Brent Pedersen's `toolshed` package. Some older `toolshed` installs (for example `toolshed-0.4.0` installed from a tarball) do not export `toolshed.files.prefunc`, which causes bwameth.py to raise:

```
AttributeError: module 'toolshed.files' has no attribute 'prefunc'
```

If you hit this error, here's the easiest option for how you got there and how to fix:

1) Install https://github.com/brentp/bwa-meth as brentp directs in his "Installation" section:

    # these 4 lines are only needed if you don't have toolshed installed
    wget https://pypi.python.org/packages/source/t/toolshed/toolshed-0.4.0.tar.gz
    tar xzvf toolshed-0.4.0.tar.gz
    cd toolshed-0.4.0
    sudo python setup.py install

    wget https://github.com/brentp/bwa-meth/archive/master.zip
    unzip master.zip
    cd bwa-meth-master/
    sudo python setup.py install

This will install in /usr/local by default.

2) Use the provided non-invasive wrapper
- This repository includes a shim at `${aroot}/scripts/bwameth-wrapper.py` that monkey-patches `toolshed.files.prefunc` at runtime then executes the installed `bwameth.py`.  
- Make it executable and put it in your PATH (or leave it in the repo and point `bwalign.sh` at it). `bwalign.sh` in this repo prefers the wrapper automatically if present.
- Example:
  - chmod +x ~/projects/toxo2/scripts/bwameth-wrapper.py
  - run the pipeline normally; bwalign will use the wrapper and you will not need to change system packages.

