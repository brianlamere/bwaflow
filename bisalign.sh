#!/usr/bin/bash

#the $1 is the task you're running.  references and targets are in sync this time.
#references:  ADNP2  AJAP1  CELF5  EFNA3  EN1  LAMBDA  PAK6  PTPN2  SUZ12

#set to exactly "yes" to send to stdout what would have been done, without running anything
dryrun="yes"

curtime=$(date "+%d%h%Y-%H.%M.%S")

tgt=`echo ${1}|tr -d '/'`

aroot="/projects/Toxo"
aref="${aroot}/references/${tgt}"
scratch="/projects/scratch"
outroot="/projects/Toxo/bisout"
outdir="${outroot}/${tgt}"
[ ! -d ${outdir} ] && mkdir -p ${outdir}

BISMARK="/projects/bOS/biosrc/Bismark/bismark"
bisargs1="--parallel 4 -p 4 -N 1 -L 16 -D 20 -R 5 --score_min L,0,-0.6"
bisargs2="--local --temp_dir $scratch $aref --output_dir ${outdir}"

LOGFILE="./logfile.out"
[ -f $LOGFILE ] && mv $LOGFILE $LOGFILE.$curtime


#previous use had hundreds of items, still better to prevent typos however
for i in `ls -d ${tgt}/*${tgt}*|tr -s '//'`
do
	echo "starting $i" |tee -a $LOGFILE
	R1=`ls ${i}/*L001_R1_001.fastq.gz`
	R2=`ls ${i}/*L001_R2_001.fastq.gz`
	IFS="/" read -ra parts1 <<< "$R1"
	outfile="${parts1[1]}.bismark.bam"

	perargs="${outdir}/${newdir}.bwameth.sam"
	outfull="${outdir}/${outfile}"
	biscmd="${BISMARK} ${bisargs1} ${bisargs2} -1 ${R1} -2 ${R2}"
        if [ "$dryrun" = "yes" ]; then
                echo "This is a dry run."
                echo -e "\e[41mI would run:\e[44m  ${biscmd}\e[0m"
        else
		echo -e "\e[41mI will run:\e[44m  ${biscmd}\e[0m" | tee -a $LOGFILE
		if ${biscmd}; then
			echo "ran this without error:\n  ${bwacmd}" >> ${LOGFILE} 
		else
			echo "We died with this:\n ${bwacmd}\n.  If we die, we stop." | tee -a ${LOGFILE}
			exit 1
		fi
        fi
done

exit 0
