#!/usr/bin/bash
# Conservative refactor of bwalign.sh to use the fastqs root and keep dryrun behavior.
# Usage examples:
#   ./bwalign.sh -n yes -r /projects/toxo2 -f /projects/toxo2/MS20251020-1 SUZ12
#   ./bwalign.sh -n no  -r /projects/toxo2 -f /projects/toxo2/MS20251020-1 SUZ12
set -euo pipefail

# defaults (edit here or override with -n/-r/-f)
dryrun="yes"                             # set to "no" to actually run
aroot="/projects/toxo2"
fastqs="/projects/toxo2/MS20251020-1"    # root containing per-reference directories (e.g. MS20251020-1/ADNP2/...)
bwameth_path="/usr/local/bin/bwameth.py" # path to bwameth wrapper (python script)
python_bin="python"

# bwameth args (array so you can adjust at top of file)
bwargs=( --threads 16 )  # --reference will be appended once we know aref

usage() {
  cat <<EOF
Usage: $0 [-n yes|no] [-r aroot] [-f fastqs_root] TARGET
  -n dryrun (yes/no)      default: ${dryrun}
  -r aroot                default: ${aroot}
  -f fastqs_root          default: ${fastqs}
  TARGET                  e.g. SUZ12
Example:
  $0 -n yes -r /projects/toxo2 -f /projects/toxo2/MS20251020-1 SUZ12
EOF
  exit 1
}

while getopts "n:r:f:h" opt; do
  case "$opt" in
    n) dryrun="$OPTARG" ;;
    r) aroot="$OPTARG" ;;
    f) fastqs="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))
tgt="${1:-}"
[ -n "$tgt" ] || usage

curtime=$(date "+%d%h%Y-%H.%M.%S")
LOGFILE="./logfile.out"
[ -f "$LOGFILE" ] && mv "$LOGFILE" "$LOGFILE.$curtime"

# find reference fasta (first fasta in that ref dir)
aref="$(ls "${aroot}/references/${tgt}"/*.fasta 2>/dev/null | head -n1 || true)"
[ -n "$aref" ] || { echo "Reference fasta not found in ${aroot}/references/${tgt}"; exit 1; }

# finalize bwargs with reference
bwargs+=( --reference "${aref}" )

# verify python and bwameth
command -v "$python_bin" >/dev/null 2>&1 || { echo "Cannot find python ($python_bin)"; exit 1; }
if [ ! -x "$bwameth_path" ]; then
    if command -v bwameth.py >/dev/null 2>&1; then
        bwameth_path="$(command -v bwameth.py)"
    else
        echo "Cannot find bwameth.py at ${bwameth_path} and not in PATH"; exit 1
    fi
fi

# outdir built from aroot so script can be run from any cwd
outdir="${aroot}/bwaout/${tgt}"
mkdir -p "${outdir}"

# helper to run an array command, optionally redirecting stdout to a file
# usage: run_cmd arr_name [outfile]
run_cmd() {
    local arr_name="$1"
    local outfile="${2-}"
    local -n cmdref="$arr_name"

    if [ "${dryrun,,}" = "yes" ]; then
        if [ -n "$outfile" ]; then
            echo "Would run: ${cmdref[*]} > $outfile"
        else
            echo "Would run: ${cmdref[*]}"
        fi
        return 0
    fi

    if [ -n "$outfile" ]; then
        "${cmdref[@]}" > "$outfile"
        return $?
    else
        "${cmdref[@]}"
        return $?
    fi
}

if [ "${dryrun,,}" = "yes" ]; then
    echo "DRY RUN MODE: no commands will be executed. The script will print the commands it would run."
fi

shopt -s nullglob
# iterate under the fastqs root for this target (matches your find output)
for sample_dir in "${fastqs}/${tgt}"/*"${tgt}"*; do
    [ -d "$sample_dir" ] || continue
    sample_dir_abs="$(cd "$sample_dir" && pwd)"
    echo "starting ${sample_dir_abs}" | tee -a "$LOGFILE"

    # find R1/R2 (take first match)
    R1s=( "${sample_dir_abs}"/*L001_R1_001.fastq.gz )
    R2s=( "${sample_dir_abs}"/*L001_R2_001.fastq.gz )
    if [ "${#R1s[@]}" -eq 0 ] || [ "${#R2s[@]}" -eq 0 ]; then
        echo "No R1/R2 fastq found in ${sample_dir_abs}, skipping" | tee -a "$LOGFILE"
        continue
    fi
    R1="${R1s[0]}"
    R2="${R2s[0]}"

    basefn="$(basename "$R1")"
    uname="${basefn%%_L00*}"
    outfile="${uname}.bwameth.sam"
    outfull="${outdir}/${outfile}"

    # build the command array for bwameth: python /path/to/bwameth.py <args> R1 R2
    bwa_cmd=( "$python_bin" "$bwameth_path" "${bwargs[@]}" "$R1" "$R2" )

    if [ "${dryrun,,}" = "yes" ]; then
        echo "Would run: ${bwa_cmd[*]} > ${outfull}"
    else
        echo -e "\e[41mI will run:\e[44m  ${bwa_cmd[*]} > ${outfull}\e[0m" | tee -a "$LOGFILE"
        if run_cmd bwa_cmd "$outfull"; then
            echo "ran this without error: ${bwa_cmd[*]}" >> "$LOGFILE"
        else
            echo "We died running: ${bwa_cmd[*]}" | tee -a "$LOGFILE"
            exit 1
        fi
    fi
done

exit 0
