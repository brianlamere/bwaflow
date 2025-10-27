#!/usr/bin/bash
# Minimal conservative refactor: centralize aroot usage, allow CLI overrides, preserve existing behavior.
set -euo pipefail

# Defaults
dryrun="yes"
curtime=$(date "+%d%h%Y-%H.%M.%S")
aroot="/projects/toxo2"     # can be overridden with -r
samcmd="/usr/bin/samtools"
mdcmd="/projects/usr/bin/MethylDackel"

usage() {
  cat <<EOF
Usage: $0 [-n yes|no] [-r aroot] TARGET
  -n dryrun (yes/no)   default: ${dryrun}
  -r aroot             default: ${aroot}
  TARGET               e.g. SUZ12
EOF
  exit 1
}

while getopts "n:r:h" opt; do
  case "$opt" in
    n) dryrun="$OPTARG" ;;
    r) aroot="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))
tgt="${1:-}"
[ -z "$tgt" ] && usage

# when you hit auto-complete tab it will have the trailing slash; remove if there
tgt="$(echo "${tgt}" | tr -d '/')"
aref="$(ls "${aroot}/references/${tgt}"/*.fasta 2>/dev/null | head -n1)"
#aref=`ls ${aroot}/references/${tgt}/*.fasta`
echo "did I get here"
[ -n "$aref" ] || { echo "Reference fasta not found in ${aroot}/references/${tgt}"; exit 1; }

# Quality threshold
qthreshold=42
mqX=".mq${qthreshold}"

# flags arrays
add_flags=()
samVopts=( view --threads 4 -q "${qthreshold}" "${add_flags[@]}" -bT "${aref}" )
samSopts=( sort --threads 4 )
samIopts=( index --threads 4 )
samSTopts=( stats )
samFopts=( faidx )

mdEopts=( extract -@ 4 )
mdCRopts=( extract -@ 4 --cytosine_report )
mdMCopts=( mergeContext )
mdMBopts=( mbias )

LOGFILE="./logfile.out"
[ -f "$LOGFILE" ] && mv "$LOGFILE" "$LOGFILE.$curtime"

samdir="${aroot}/bwaout/${tgt}"
bamdir="${aroot}/bamfiles/${tgt}"
repdir="${aroot}/bwareports/${tgt}"
mkdir -p "${samdir}" "${bamdir}" "${repdir}"

# run_cmd helper (array + optional redirect)
run_cmd() {
    local arr_name="$1"; local outfile="${2-}"; local -n cmdref="$arr_name"
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
    echo "DRY RUN MODE: no commands will be executed. The script will print what it would run."
fi

# this need only happen once...
runFsam=( "$samcmd" "${samFopts[@]}" "${aref}" )
if [ "${dryrun,,}" = "yes" ]; then
    run_cmd runFsam
else
    if run_cmd runFsam; then
           echo "ran CMD without error: ${runFsam[*]}" >> ${LOGFILE}
    else
           echo "We died with this: ${runFsam[*]}" >> ${LOGFILE}
           exit 1
    fi
fi

shopt -s nullglob
for i in "${tgt}"/*"${tgt}"*; do
    [ -d "$i" ] || continue
    echo -e "\e[104m#### starting ${i} #########\e[0m" | tee -a "$LOGFILE"

    R1s=( "$i"/*L001_R1_001.fastq.gz )
    if [ "${#R1s[@]}" -eq 0 ]; then
        echo "No R1 fastq found in ${i}, skipping" | tee -a "${LOGFILE}"
        continue
    fi
    R1="${R1s[0]}"

    basefn="$(basename "$R1")"
    uname="${basefn%%_L00*}"

    samfile="${uname}.bwameth.sam"
    osamfull="${samdir}/${samfile}"
    newbam="${uname}${mqX}.bwameth.bam"
    nbamfull="${bamdir}/${newbam}"
    sortbam="${uname}${mqX}.sorted.bwameth.bam"
    sbamfull="${bamdir}/${sortbam}"
    statsfile="${repdir}/${uname}.bam.stats"
    idxstatsf="${repdir}/${uname}.bam.idxstats"

    runVsam=( "$samcmd" "${samVopts[@]}" "$osamfull" -o "$nbamfull" )
    runSsam=( "$samcmd" "${samSopts[@]}" "$nbamfull" -o "$sbamfull" )
    runIsam=( "$samcmd" "${samIopts[@]}" "$sbamfull" )
    runSTsam=( "$samcmd" "${samSTopts[@]}" "$sbamfull" )

    mdpreF="${repdir}/${uname}"
    runEmd=( "$mdcmd" "${mdEopts[@]}" "${aref}" "$sbamfull" -o "${mdpreF}" )
    runCRmd=( "$mdcmd" "${mdCRopts[@]}" "${aref}" "$sbamfull" -o "${mdpreF}" )
    runMCmd=( "$mdcmd" "${mdMCopts[@]}" "${aref}" "${mdpreF}_CpG.bedGraph" -o "${mdpreF}.mergeContext" )
    runMBmd=( "$mdcmd" "${mdMBopts[@]}" "${aref}" "${mdpreF}_CpG.bedGraph" "${mdpreF}" )

    cmd_arrays=( runVsam runSsam runIsam runEmd runCRmd runMCmd runSTsam runMBmd )
    for arr in "${cmd_arrays[@]}"; do
        if [ "$arr" = "runSTsam" ]; then
            if [ "${dryrun,,}" = "yes" ]; then
                run_cmd "$arr" "$statsfile"
            else
                echo -e "\e[41mI will run:\e[44m  ${runSTsam[*]} > ${statsfile}\e[0m"
                if run_cmd "$arr" "$statsfile"; then
                    echo "ran CMD without error: ${arr} > ${statsfile}" >> ${LOGFILE}
                else
                    echo "We died with this: ${arr} > ${statsfile}" >> ${LOGFILE}
                    exit 1
                fi
            fi
        else
            if [ "${dryrun,,}" = "yes" ]; then
                run_cmd "$arr"
            else
                echo -e "\e[41mI will run:\e[44m  ${!arr} \e[0m"
                if run_cmd "$arr"; then
                    echo "ran CMD without error: ${arr}" >> ${LOGFILE}
                else
                    echo "We died with this: ${arr}" >> ${LOGFILE}
                    exit 1
                fi
            fi
        fi
    done
done

exit 0
