#!/usr/bin/env bash
# Rename directories like:
#   167CC_SUZ12_ds.926467c63d684c3e88816efde96615a2
# to:
#   167CC_SUZ12_S46
# where "S46" is the 3rd underscore-delimited component of a file inside the directory
#
# Usage:
#   ./rename_ds_dirs.sh        # dry-run (shows what would be done)
#   ./rename_ds_dirs.sh -a     # actually perform the renames
#   ./rename_ds_dirs.sh -av    # apply + verbose
#
set -euo pipefail

apply=0
verbose=0

usage() {
  cat <<EOF
Usage: $0 [-a] [-v] [-h]
  -a    apply changes (default = dry-run)
  -v    verbose
  -h    show this help
EOF
  exit 1
}

while getopts "avh" opt; do
  case "$opt" in
    a) apply=1 ;;
    v) verbose=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

shopt -s nullglob

# iterate over directories in current directory (one level)
for d in */; do
  # remove trailing slash
  dir="${d%/}"

  # only consider directories that match the _ds.<hash> pattern
  if [[ "$dir" != *_ds.* ]]; then
    [[ $verbose -eq 1 ]] && printf "Skipping '%s' (no _ds. pattern)\n" "$dir"
    continue
  fi

  # find a sample file name inside (first file)
  sample_file=$(find "$dir" -maxdepth 1 -type f -printf '%f\n' | head -n 1 || true)

  if [[ -z "$sample_file" ]]; then
    printf "No files found inside '%s', skipping\n" "$dir"
    continue
  fi

  # extract the 3rd underscore-delimited component
  # e.g. 167CC_SUZ12_S46_L001_R1_001.fastq.gz -> S46
  third_component=$(awk -F'_' '{print $3}' <<<"$sample_file" | tr -d '\r\n')

  if [[ -z "$third_component" ]]; then
    printf "Could not determine 3rd component from '%s' in '%s', skipping\n" "$sample_file" "$dir"
    continue
  fi

  # prefix is everything before _ds.<hash>
  prefix="${dir%%_ds.*}"
  new_name="${prefix}_${third_component}"

  if [[ "$new_name" == "$dir" ]]; then
    [[ $verbose -eq 1 ]] && printf "Target name for '%s' already '%s', skipping\n" "$dir" "$new_name"
    continue
  fi

  if [[ -e "$new_name" ]]; then
    printf "Target '%s' already exists, skipping rename of '%s'\n" "$new_name" "$dir"
    continue
  fi

  printf "Would rename: '%s' -> '%s'\n" "$dir" "$new_name"
  if [[ $apply -eq 1 ]]; then
    mv -- "$dir" "$new_name"
    printf "Renamed: '%s' -> '%s'\n" "$dir" "$new_name"
  fi
done
