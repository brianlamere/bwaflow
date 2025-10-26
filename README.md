# bwaflow — small shell-based bisulfite alignment + reporting helpers

This repository contains lightweight shell scripts I used to run targeted bisulfite sequencing projects:
- rename_ds.dirs.sh — tidy up Illumina / BaseSpace download folders
- bwalign.sh — run bwameth.py (bwa mem2 wrapper) to align paired-end FASTQs producing SAMs
- pipelineArray.sh / pipelineMD.sh — run samtools + MethylDackel on SAM/BAMs to produce QC and methylation reports

These scripts are intentionally conservative and simple (shell + arrays). They expect a small, consistent directory layout (described below). They provide a `dryrun` mode so you can inspect commands before they run — strongly recommended for your first run.

Table of contents
- Requirements
- Expected project layout
- Quick workflow (1–8)
- Script usage examples
- Common config knobs and where to change them
- Troubleshooting & tips
- Contributing / contact

---

## Requirements
Install these tools and make sure they are on PATH or edit the script variables pointing to their locations:
- Python (for bwameth.py) — `python`
- bwameth.py — the bwameth wrapper for bwa mem2 (installable via the project that provided it)
- bwa mem2 (bwameth uses it)
- samtools
- MethylDackel
- Optional: bs (BaseSpace CLI) if you use it to download directly

Also: a Unix-like shell (the scripts use bash and rely on bash arrays and `local -n` name references).

---

## Expected directory layout

The scripts assume a project root (variable `aroot` in scripts). Inside that:

- References:
  - `${aroot}/references/<REFNAME>/<REFNAME>.fasta`
  - Example: `/projects/toxo2/references/SUZ12/SUZ12.fasta`

- FASTQ download root (the `fastqs` directory):
  - Example: `/projects/toxo2/MS20251020-1`
  - Under that: a directory per reference (must match reference dir name exactly — case-sensitive)
  - Under the reference directory: one directory per sample (renamed by `rename_ds.dirs.sh`) containing:
    - `<SAMPLE>_L001_R1_001.fastq.gz`
    - `<SAMPLE>_L001_R2_001.fastq.gz`

Example:
```
/projects/toxo2
├─ references/
│  ├─ SUZ12/
│  │  └─ SUZ12.fasta
├─ MS20251020-1/
│  ├─ SUZ12/
│  │  ├─ 167CC_SUZ12_S46/
│  │  │  ├─ 167CC_SUZ12_S46_L001_R1_001.fastq.gz
│  │  │  └─ 167CC_SUZ12_S46_L001_R2_001.fastq.gz
│  │  └─ ...
├─ bwaout/
├─ bamfiles/
└─ bwareports/
```

Notes:
- The reference directory name must match the top-level subdirectory under the FASTQ root (case-sensitive).
- `rename_ds.dirs.sh` converts raw BaseSpace download folder names like `167CC_SUZ12_ds.<hash>` into `167CC_SUZ12_S46` (it infers the S### token from filenames inside). Use it before alignment.

---

## Quick workflow (1–8)

1. Create a project directory if you haven’t already (`aroot`).
2. Create references under `${aroot}/references/<REFNAME>/` and place the single FASTA there.
3. Index the reference for bwameth (example wrapper):
   - Example: `bwameth.py index-mem2 references/ADNP2/ADNP2.fasta`
   - (This produces whatever index files bwameth expects)
4. Download FASTQs from BaseSpace into a single directory (e.g. `/projects/toxo2/MS20251020-1`), preserving per-reference subdirectories.
5. Clean up the BaseSpace directory names:
   - cd into `MS20251020-1/<REFNAME>` and run:
     - `./rename_ds.dirs.sh`  (prints a dry-run)
     - `./rename_ds.dirs.sh -a`  (actually rename)
6. Align with bwameth:
   - Dry-run example (inspect commands):
     - `./bwalign.sh -n yes -r /projects/toxo2 -f /projects/toxo2/MS20251020-1 SUZ12`
   - Real run (be careful, CPU heavy):
     - `./bwalign.sh -n no -r /projects/toxo2 -f /projects/toxo2/MS20251020-1 SUZ12`
   - Output SAMs will go to `${aroot}/bwaout/<REFNAME>/`.
7. Run the processing pipeline on the SAM/BAM files:
   - Dry-run:
     - `./pipelineArray.sh -n yes -r /projects/toxo2 SUZ12`
   - Real run:
     - `./pipelineArray.sh -n no -r /projects/toxo2 SUZ12`
   - Outputs (BAMs, sorted BAMs, reports) will go to:
     - `${aroot}/bamfiles/<REFNAME>/`
     - `${aroot}/bwareports/<REFNAME>/`
8. Deliver `${aroot}/bwareports/<REFNAME>/` to the scientist.

---

## Script overview & important flags

- rename_ds.dirs.sh
  - Purpose: rename BaseSpace `_ds.<hash>` directories to a nicer `<prefix>_S###` name using a filename inside the dir.
  - Usage:
    - Dry-run: `./rename_ds.dirs.sh`
    - Apply: `./rename_ds.dirs.sh -a`
    - Verbose: `-v`
  - Behaviour: operates on directories in the current working directory; run it in the per-reference directory under your fastqs root.

- bwalign.sh
  - Purpose: run bwameth.py to align paired-end FASTQs and write per-sample SAM files.
  - Key options (in the refactored script):
    - `-n yes|no` — dry-run (default `yes`)
    - `-r <aroot>` — project root (default set in script)
    - `-f <fastqs_root>` — fastq root (default set in script)
  - Example:
    - `./bwalign.sh -n yes -r /projects/toxo2 -f /projects/toxo2/MS20251020-1 SUZ12`
    - `./bwalign.sh -n no -r /projects/toxo2 -f /projects/toxo2/MS20251020-1 SUZ12`

- pipelineArray.sh (and pipelineMD.sh — older variant)
  - Purpose: run samtools steps, MethylDackel extract/mergeContext/mbias, and generate reports.
  - Key options:
    - `-n yes|no` — dry-run (default `yes`)
    - `-r <aroot>` — project root (default set in script)
  - Important config at the top of the script:
    - `qthreshold` — mapping quality threshold (used for filenames and samtools -q)
    - arrays like `samVopts`, `samSopts`, `mdEopts` — edit near top to change behavior
  - The helper `run_cmd` safely executes array-built commands; `samtools stats` outputs to STDOUT and the script captures it via redirection internally (no temp file needed).

---

## Configuration knobs (where to edit)
The scripts maintain all frequently-changed settings near the top:
- `aroot` — project root (change or pass with `-r` if supported)
- `fastqs` — fastq root for bwalign (`-f` in bwalign.sh)
- `dryrun` — set to `"yes"` (safe default) or `"no"` to execute
- `qthreshold` — mapping quality threshold used by samtools and reflected in output filenames
- `add_flags`, `bwargs`, `samVopts`, `mdEopts`, etc. — arrays of tool options you can edit to change tool behavior

Prefer editing the top-of-file arrays instead of changing internals.

---

## Dry-run philosophy — why it helps
- Dry-run prints the full command and target file(s) for each sample without executing anything.
- This lets you randomly copy a command and run it interactively to validate paths, options, and resource usage before unleashing hundreds of jobs.
- Default mode in the provided scripts is dry-run to prevent accidental mass-execution.

---

## Tips & troubleshooting

- Case sensitivity: reference names are matched exactly. If your scientist supplies `Lambda` but the reference dir is `LAMBDA`, pick one and document it in your project README. I recommend using UPPERCASE consistently for reference names.
- Missing reference FASTA: the scripts look for the first `*.fasta` in `${aroot}/references/${tgt}`; if there are none the script will exit with an error.
- Missing FASTQs: if no R1/R2 are found under the expected sample dir, that sample is skipped and a message is logged. Use dry-run to discover mismatches.
- Check binaries: run `command -v samtools`, `command -v bwameth.py`, and `command -v MethylDackel` to verify paths. You can edit script variables to point to non-standard locations.
- Logging: scripts append to `./logfile.out` in the CWD. Consider running them from the project root or redirecting logs elsewhere.
- Scaling: bwameth can be CPU and IO-heavy. Either run per-sample sequentially using multiple threads per job, or batch many samples with fewer threads per job (e.g., use GNU parallel / xargs -P and reduce per-job `--threads`).
- Disk usage: SAM files are big. If you need to reduce disk usage, consider piping SAM->BAM compression in the alignment step (this changes downstream expectations) or delete intermediate files after downstream steps succeed.

---

## Example quick check workflow (recommended)
1. Prepare references and index with bwameth index command.
2. Download fastqs into `${fastqs}`.
3. cd into `${fastqs}/${REFNAME}` and run:
   - `./rename_ds.dirs.sh` (inspect)
   - `./rename_ds.dirs.sh -a` (apply)
4. From project root, dry-run alignment:
   - `./bwalign.sh -n yes -r /projects/toxo2 -f /projects/toxo2/MS20251020-1 SUZ12`
5. Pick one printed command and run it manually to ensure SAM is produced at the expected path.
6. Dry-run pipeline:
   - `./pipelineArray.sh -n yes -r /projects/toxo2 SUZ12`
7. After manual checks, run real jobs:
   - `./bwalign.sh -n no -r /projects/toxo2 -f /projects/toxo2/MS20251020-1 SUZ12`
   - `./pipelineArray.sh -n no -r /projects/toxo2 SUZ12`

---

## Notes on conservative edits & future improvements
This repo is intentionally small and shell-based. If you want to expand it later, conservative next steps:
- Add a wrapper `run_project.sh` or Makefile to orchestrate the 8-step workflow.
- Add `--limit N` for test runs (process only first N samples).
- Add unit / integration tests (smoke tests) to validate a sample command end-to-end.
- Convert logging to timestamped per-sample logfiles if you want finer granularity.
- Consider rewriting in Python for better error handling if project complexity increases significantly.

---

## Contact / issues
If you find a bug or want a small enhancement, open an issue in this repository with:
- command you ran (include `-n yes` output if dry-run)
- a short description of the mismatch you observed
- a sample path listing if helpful

---

License / attribution
- These are small personal scripts; include your preferred license file in the repo if you want to share or publish them widely.

Thanks — and remember: dry-run first, especially when you have hundreds of samples.
