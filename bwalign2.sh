#!/usr/bin/bash
# Conservative refactor of bwalign.sh with TrimGalore "val_" detection.
# - Prefers *_val_1 / *_val_2 trimmed fastqs if present in the sample dir
# - Falls back to original L001_R1/R2 naming
# - Supports a non-invasive bwameth wrapper (preferred if present)
# - Dry-run mode prints the exact commands that would be executed
# - Can operate on a fastqs root whose subdirectory names do NOT match the reference.
#   When invoked with -f /path/to/val_bsfiles/BG and TARGET LCP1, the outputs will be
#   written under aroot/{bwaout,bamfiles,bwareports}/BG_LCP1/<sample> and filenames
#   will include the TARGET (reference) for clarity, e.g. CB131_LCP1.flagstat.txt
set -euo pipefail

# defaults (edit here or override with -n/-r/-f)
dryrun="yes"                   # set to "no" to actually run
aroot="/projects/toxo3"
fastqs="/projects/toxo3/val_MS20251020-1"    # root containing per-sample directories (can be a subdir like .../val_bsfiles/BG)
bwameth_path="/usr/local/bin/bwameth.py" # path to bwameth wrapper (python script)
bwameth_wrapper="${BWAMETH_WRAPPER:-${aroot}/scripts/bwameth-wrapper.py}" # preferred non-invasive shim
python_bin="python"

# bwameth args (array so you can adjust at top of file)
bwargs=( --threads 16 )  # --reference will be appended once we know aref

usage() {
  cat <<EOF
Usage: $0 [-n yes|no] [-r aroot] [-f fastqs_root] TARGET
  -n dryrun (yes/no)      default: ${dryrun}
  -r aroot                default: ${aroot}
  -f fastqs_root          default: ${fastqs}
                          This may be a directory whose subdirectories contain paired FASTQs.
                          The origin name (basename of this fastqs_root) will be combined with
                          TARGET for output dirs, e.g. <aroot>/bwaout/BG_LCP1/<sample>
  TARGET                  e.g. SUZ12
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

# Resolve bwameth execution method:
bwameth_exec=""
if [ -f "${bwameth_wrapper}" ]; then
    if [ -x "${bwameth_wrapper}" ]; then
        bwameth_exec="${bwameth_wrapper}"
    else
        echo "Warning: bwameth wrapper '${bwameth_wrapper}' exists but is not executable." | tee -a "$LOGFILE"
        echo "You can fix with: chmod +x ${bwameth_wrapper}" | tee -a "$LOGFILE"
        # fall back to system bwameth if available
    fi
fi

if [ -z "${bwameth_exec}" ]; then
    if [ -x "${bwameth_path}" ]; then
        bwameth_exec="${python_bin} ${bwameth_path}"
    else
        if command -v bwameth.py >/dev/null 2>&1; then
            bwameth_exec="$(command -v bwameth.py)"
        else
            echo "Cannot find bwameth wrapper nor system bwameth.py; please install or provide ${bwameth_wrapper}" | tee -a "$LOGFILE"
            exit 1
        fi
    fi
fi

# derive origin name from fastqs root (basename), used to build combined output dirs
origin="$(basename "$fastqs")"
combined="${origin}_${tgt}"

# top-level outdirs built from aroot so script can be run from any cwd
outdir="${aroot}/bwaout/${combined}"
bamdir="${aroot}/bamfiles/${combined}"
repdir="${aroot}/bwareports/${combined}"
mkdir -p "${outdir}" "${bamdir}" "${repdir}"

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
# iterate all subdirectories under the fastqs root (we do NOT require the subdir names to match TARGET)
for sample_dir in "${fastqs}"/*; do
    [ -d "$sample_dir" ] || continue
    sample_dir_abs="$(cd "$sample_dir" && pwd)"
    echo -e "\n#### starting ${sample_dir_abs} ####" | tee -a "$LOGFILE"

    # Prefer TrimGalore outputs if present: *_val_1 / *_val_2 (handles .fq, .fastq, gz)
    val_r1=( "${sample_dir_abs}"/*_val_1.fastq* "${sample_dir_abs}"/*_val_1.fq* )
    val_r2=( "${sample_dir_abs}"/*_val_2.fastq* "${sample_dir_abs}"/*_val_2.fq* )

    if [[ -n "${val_r1[0]:-}" && -n "${val_r2[0]:-}" ]]; then
        echo "Found TrimGalore trimmed files in ${sample_dir_abs}; using those." | tee -a "$LOGFILE"
        R1="${val_r1[0]}"
        R2="${val_r2[0]}"
    else
        # fallback to original Illumina naming
        R1s=( "${sample_dir_abs}"/*L001_R1_001.fastq* "${sample_dir_abs}"/*_R1_001.fastq* "${sample_dir_abs}"/*_R1_001.fq* )
        R2s=( "${sample_dir_abs}"/*L001_R2_001.fastq* "${sample_dir_abs}"/*_R2_001.fastq* "${sample_dir_abs}"/*_R2_001.fq* )
        if [ "${#R1s[@]}" -eq 0 ] || [ "${#R2s[@]}" -eq 0 ]; then
            echo "No paired FASTQs (val_ or L001_R*_001) found in ${sample_dir_abs}; skipping" | tee -a "$LOGFILE"
            continue
        fi
        R1="${R1s[0]}"
        R2="${R2s[0]}"
        echo "Using raw FASTQs: $(basename "$R1") , $(basename "$R2")" | tee -a "$LOGFILE"
    fi

    # derive sample base name (strip lane/read/suffix)
    basefn="$(basename "$R1")"
    uname="${basefn%%_L00*}"
    # If using TrimGalore val_ files they often look like sample_R1_val_1.fq.gz,
    # so fallback to stripping "_val" style if needed:
    uname="${uname%%_val_*}"

    # per-sample subdirectories under the combined output dirs
    sample_outdir="${outdir}/${uname}"
    sample_bamdir="${bamdir}/${uname}"
    sample_repdir="${repdir}/${uname}"
    mkdir -p "${sample_outdir}" "${sample_bamdir}" "${sample_repdir}"

    # include TARGET (reference) in output filenames for clarity
    samfile="${uname}_${tgt}.bwameth.sam"
    outfull="${sample_outdir}/${samfile}"

    # Build bwameth command array depending on bwameth_exec form
    if [[ "${bwameth_exec}" == *" "* ]]; then
        read -r pybin scriptpath <<<"${bwameth_exec}"
        bwa_cmd=( "$pybin" "$scriptpath" "${bwargs[@]}" "$R1" "$R2" )
    else
        bwa_cmd=( "${bwameth_exec}" "${bwargs[@]}" "$R1" "$R2" )
    fi

    if [ "${dryrun,,}" = "yes" ]; then
        echo "Would run: ${bwa_cmd[*]} > ${outfull}" | tee -a "$LOGFILE"
    else
        echo -e "\e[41mI will run:\e[44m  ${bwa_cmd[*]} > ${outfull}\e[0m" | tee -a "$LOGFILE"
        if run_cmd bwa_cmd "$outfull"; then
            echo "ran this without error: ${bwa_cmd[*]}" >> "$LOGFILE"
        else
            echo "We died running: ${bwa_cmd[*]}" | tee -a "$LOGFILE"
            exit 1
        fi
    fi

    # Post-processing: convert SAM -> BAM, sort, index, and write flagstat to sample-specific repdir
    # Filenames include the reference (TARGET) so it's obvious which reference was used.
    if command -v samtools >/dev/null 2>&1; then
        # convert to BAM (samtools view -bS)
        bam_unsorted="${sample_bamdir}/${uname}_${tgt}.unsorted.bam"
        bam_final="${sample_bamdir}/${uname}_${tgt}.bam"
        bam_sorted_tmp="${sample_bamdir}/${uname}_${tgt}.sorted.bam"

        view_cmd=( samtools view -bS "${outfull}" )
        echo "Converting SAM to BAM: ${view_cmd[*]} -> ${bam_unsorted}" | tee -a "$LOGFILE"
        if run_cmd view_cmd "${bam_unsorted}"; then
            echo "samtools view produced ${bam_unsorted}" >> "$LOGFILE"
        else
            echo "samtools view failed on ${outfull}" | tee -a "$LOGFILE"
            exit 1
        fi

        # sort BAM
        sort_cmd=( samtools sort -o "${bam_sorted_tmp}" "${bam_unsorted}" )
        echo "Sorting BAM: ${sort_cmd[*]}" | tee -a "$LOGFILE"
        if run_cmd sort_cmd; then
            echo "samtools sort produced ${bam_sorted_tmp}" >> "$LOGFILE"
        else
            echo "samtools sort failed on ${bam_unsorted}" | tee -a "$LOGFILE"
            exit 1
        fi

        # move sorted to final path (atomically)
        mv_cmd=( mv "${bam_sorted_tmp}" "${bam_final}" )
        if run_cmd mv_cmd; then
            echo "Moved sorted BAM to ${bam_final}" >> "$LOGFILE"
            # cleanup unsorted
            rm -f "${bam_unsorted}"
        else
            echo "Failed to move sorted BAM into place" | tee -a "$LOGFILE"
            exit 1
        fi

        # index BAM
        idx_cmd=( samtools index "${bam_final}" )
        echo "Indexing BAM: ${idx_cmd[*]}" | tee -a "$LOGFILE"
        if run_cmd idx_cmd; then
            echo "Indexed ${bam_final}" >> "$LOGFILE"
        else
            echo "samtools index failed on ${bam_final}" | tee -a "$LOGFILE"
            exit 1
        fi

        # flagstat/report (report filename includes reference)
        flag_out="${sample_repdir}/${uname}_${tgt}.flagstat.txt"
        flag_cmd=( samtools flagstat "${bam_final}" )
        echo "Writing flagstat to ${flag_out}" | tee -a "$LOGFILE"
        if run_cmd flag_cmd "${flag_out}"; then
            echo "wrote ${flag_out}" >> "$LOGFILE"
        else
            echo "samtools flagstat failed on ${bam_final}" | tee -a "$LOGFILE"
            exit 1
        fi
    else
        echo "samtools not found; skipping BAM conversion and reports for ${outfull}" | tee -a "$LOGFILE"
    fi
done

exit 0
