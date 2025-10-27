#!/usr/bin/env bash
set -euo pipefail

# Usage: prepTG.sh [-n yes|no] [-t THREADS] [-l MINLEN] [-o OUTROOT] [-L LIMIT] [-q VALUE] FASTQ_ROOT REFNAME
dryrun="yes"; threads=4; minlen=50; outroot=""; limit=0
default_q=20; quality_mode="default"; quality_value=""

trim_galore_bin="$(command -v trim_galore || true)"
[ -n "$trim_galore_bin" ] || { echo "trim_galore not found"; exit 1; }

usage(){ cat <<EOF
Usage: $0 [-n yes|no] [-t THREADS] [-l MINLEN] [-o OUTROOT] [-L LIMIT] [-q VALUE] FASTQ_ROOT REFNAME
 -q VALUE : integer 0-60 or 'off' (default: ${default_q})
EOF
exit 1; }

while getopts "n:t:l:o:L:q:h" opt; do
  case "$opt" in
    n) dryrun="$OPTARG" ;;
    t) threads="$OPTARG" ;;
    l) minlen="$OPTARG" ;;
    o) outroot="$OPTARG" ;;
    L) limit="$OPTARG" ;;
    q)
       qarg="$OPTARG"
       if [[ "$qarg" == "off" ]]; then quality_mode="off"
       elif [[ "$qarg" =~ ^[0-9]+$ ]] && (( qarg>=0 && qarg<=60 )); then quality_mode="number"; quality_value="$qarg"
       else echo "Invalid -q"; exit 1; fi
       ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

fastq_root="${1:-}"; refname="${2:-}"
[ -n "$fastq_root" -a -n "$refname" ] || usage

# default outroot = parent/val_<basename_of_FASTQ_ROOT>
if [ -z "$outroot" ]; then
  parent="$(cd "$(dirname "$fastq_root")" && pwd)"; base="$(basename "$fastq_root")"
  outroot="${parent}/val_${base}"
fi
mkdir -p "$outroot"

# quality args for trim_galore
tgq_args=()
if [ "$quality_mode" = "off" ]; then
  tgq_args+=( "--no_quality_trimming" )
elif [ "$quality_mode" = "number" ]; then
  tgq_args+=( "-q" "$quality_value" )
else
  tgq_args+=( "-q" "${default_q}" )
fi

refdir="${fastq_root%/}/${refname}"
[ -d "$refdir" ] || { echo "Missing refdir $refdir"; exit 1; }

shopt -s nullglob
count=0
for sample_dir in "${refdir}"/*; do
  [ -d "$sample_dir" ] || continue
  count=$((count+1)); [ "$limit" -gt 0 -a "$count" -gt "$limit" ] && break
  echo "Processing $sample_dir"

  R1s=( "$sample_dir"/*L001_R1_001.fastq* "$sample_dir"/*_R1_001.fastq* )
  R2s=( "$sample_dir"/*L001_R2_001.fastq* "$sample_dir"/*_R2_001.fastq* )
  if [ "${#R1s[@]}" -eq 0 ] || [ "${#R2s[@]}" -eq 0 ]; then
    echo "No paired FASTQs in $sample_dir, skipping"; continue
  fi
  R1="${R1s[0]}"; R2="${R2s[0]}"

  sample="$(basename "$sample_dir")"
  outdir="${outroot}/${refname}/${sample}"; mkdir -p "$outdir"

  tg_cmd=( "$trim_galore_bin" --paired -j "$threads" "${tgq_args[@]}" --length "$minlen" -o "$outdir" "$R1" "$R2" )
  if [ "${dryrun,,}" = "yes" ]; then
    echo "Would run: ${tg_cmd[*]}"
  else
    "${tg_cmd[@]}"
  fi
done

echo "Done. Processed $count samples."
