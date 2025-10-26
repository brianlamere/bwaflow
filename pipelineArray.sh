#!/usr/bin/bash
# the intent of this is to be as absolutely readable/understable as possible
# put things readers will need to know, at the very top.
# put things you *might* change, near the top.

# set to "yes" to only print the commands that would be run (dry run)
dryrun="yes"

# the $1 is the task you're running.
# references and targets are in sync for the current targets.
# references:  ADNP2  AJAP1  CELF5  EFNA3  EN1  LAMBDA  PAK6  PTPN2  SUZ12

curtime=$(date "+%d%h%Y-%H.%M.%S")
aroot="/projects/toxo2"
samcmd="/usr/bin/samtools"
mdcmd="/projects/usr/bin/MethylDackel"

# when you hit auto-complete tab it will have the trailing slash; remove if there
tgt=`echo ${1}|tr -d '/'`
# the next line will cause problems if there is more than 1 fasta file in that directory.
aref=`ls ${aroot}/references/${tgt}/*.fasta`

# Quality threshold variable so you only need to change one place
qthreshold=42
mqX=".mq${qthreshold}" # filename marker indicating mapping-quality threshold

# If you want to add the --add-flags option back in, set add_flags to that token string.
# e.g. add_flags=(--add-flags 0x2)
add_flags=() # empty by default

# Define samtools/methylDackel options as arrays (so we can safely build command arrays)
# Keep them near top for easy editing.
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
[ -f $LOGFILE ] && mv $LOGFILE $LOGFILE.$curtime

samdir="/projects/Toxo/bwaout/${tgt}"
bamdir="/projects/Toxo/bamfiles/${tgt}"
[ ! -d ${bamdir} ] && mkdir -p ${bamdir}
repdir="/projects/Toxo/bwareports/${tgt}"
[ ! -d ${repdir} ] && mkdir -p ${repdir}

# Helper to run a command stored in an array variable, optionally redirecting stdout to a file.
# Usage:
#   run_cmd arrname          # runs the array command
#   run_cmd arrname outfile  # runs the array command and redirects stdout to outfile
# NOTE: uses bash name-reference (local -n) to avoid eval and preserve argument boundaries.
run_cmd() {
    local arr_name="$1"
    local outfile="${2-}"
    local -n cmdref="$arr_name"

    if [ "${dryrun,,}" = "yes" ]; then
        # Print a single concise "would run" line (no "This is a dry run" per-command spam)
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

# If user selected dryrun at top, print a single banner to make it obvious and continue.
if [ "${dryrun,,}" = "yes" ]; then
    echo "DRY RUN MODE: no commands will be executed. The script will print the commands it would run."
fi

# this need only happen once... (runFsam should go through run_cmd so dryrun works)
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

# iterate over directories that match pattern (kept compatibility with original loop)
shopt -s nullglob
for i in `ls -d ${tgt}/*${tgt}*|tr -s '//'`; do
    echo -e "\e[104m#### starting ${i} #########\e[0m" |tee -a $LOGFILE

    R1=`ls ${i}/*L001_R1_001.fastq.gz 2>/dev/null || true`
    if [ -z "$R1" ]; then
        echo "No R1 fastq found in ${i}, skipping" | tee -a ${LOGFILE}
        continue
    fi

    # derive sample base name (strip lane/read/suffix)
    basefn=$(basename "$R1")
    # strip from first _L00... onward (handles filenames like sample_L001_R1_001.fastq.gz)
    uname="${basefn%%_L00*}"

    samfile="${uname}.bwameth.sam"
    osamfull="${samdir}/${samfile}"
    newbam="${uname}${mqX}.bwameth.bam"
    nbamfull="${bamdir}/${newbam}"
    sortbam="${uname}${mqX}.sorted.bwameth.bam"
    sbamfull="${bamdir}/${sortbam}"
    statsfile="${repdir}/${uname}.bam.stats"
    idxstatsf="${repdir}/${uname}.bam.idxstats"

    # build the command arrays
    runVsam=( "$samcmd" "${samVopts[@]}" "$osamfull" -o "$nbamfull" )
    runSsam=( "$samcmd" "${samSopts[@]}" "$nbamfull" -o "$sbamfull" )
    runIsam=( "$samcmd" "${samIopts[@]}" "$sbamfull" )
    # samtools stats writes to stdout; we'll capture that by redirecting to statsfile when running
    runSTsam=( "$samcmd" "${samSTopts[@]}" "$sbamfull" )

    mdpreF="${repdir}/${uname}"
    runEmd=( "$mdcmd" "${mdEopts[@]}" "${aref}" "$sbamfull" -o "${mdpreF}" )
    runCRmd=( "$mdcmd" "${mdCRopts[@]}" "${aref}" "$sbamfull" -o "${mdpreF}" )
    runMCmd=( "$mdcmd" "${mdMCopts[@]}" "${aref}" "${mdpreF}_CpG.bedGraph" -o "${mdpreF}.mergeContext" )
    runMBmd=( "$mdcmd" "${mdMBopts[@]}" "${aref}" "${mdpreF}_CpG.bedGraph" "${mdpreF}" )

    # Execute commands in order. For samtools stats (stdout-only) pass the outfile to run_cmd so it will be redirected.
    cmd_arrays=( runVsam runSsam runIsam runEmd runCRmd runMCmd runSTsam runMBmd )
    for arr in "${cmd_arrays[@]}"; do
        if [ "$arr" = "runSTsam" ]; then
            # stats writes to stdout; provide the target file to run_cmd so run_cmd will redirect it.
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
                # print the command being run for logging/visibility
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

# restore IFS if you changed it elsewhere (keeps original behavior safe)
IFS=$' \t\n'

exit 0
