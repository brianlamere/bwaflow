#!/usr/bin/bash
#it is intended that this is used in the /projects/ckmout directory from previous tools.
#were I sharing this with others I would make it less picky.
#not deduplicating changes a lot about this, but I don't want to toss this version.
#also adding samtools MQ filter 
#arg1 is directory to be pipelined
#arg2 is source for reference genome

curtime=$(date "+%d%h%Y-%H.%M.%S")
samcmd="/usr/bin/samtools"
samopts="view --threads 4 -q 30 -b"
#samopts="view --threads 4 -b"
#change next line to ".bam" if no samtools for mq, or .mqX.bam if so
mqX=".mq30.bam"
#mqX=".bam"
broot="/projects/bOS/biosrc/Bismark"
bmecmd="$broot/bismark_methylation_extractor"
bmeopts="--bedGraph -p --comprehensive --parallel 4 --cytosine_report --genome_folder"
c2ccmd="$broot/coverage2cytosine"
b2ncmd="$broot/bam2nuc"
b2rcmd="$broot/bismark2report"


LOGFILE="./logfile2.out"

[ -f $LOGFILE ] && mv $LOGFILE $LOGFILE.$curtime

for i in `ls -d ${1}/${1}*|tr -s '//'`
do
	obamlong=`ls $i/*pe.bam`
	oreplong=`ls $i/*report.txt`
	IFS="/" read -ra pobam <<< "${obamlong}"
	IFS="/" read -ra porep <<< "${oreplong}"
	runname="${pobam[1]}"
	obamfile="${pobam[2]}"
	orepfile="${porep[2]}"
	echo -e "\e[104m#### starting ${runname} #########\e[0m"

	repdir="${i}/reports"
	[ ! -d ${repdir} ] && mkdir -p ${repdir}

	#copy (not move! can't be quickly replaced like other reports) alignment report to reports directory
	cprep="cp ${obamlong::-6}PE_report.txt ${repdir}/"
	newbam="${obamfile::-4}${mqX}"
	runsam="${samcmd} ${samopts} ${obamlong} -o ${i}/${newbam}"
	runbme="${bmecmd} ${bmeopts} ${2} -o ${repdir} ${i}/${newbam}"
	covfile="${repdir}/${newbam::-4}.bismark.cov.gz"
	runc2c="${c2ccmd} -genome_folder ${2} -o ${newbam} --dir ${repdir} ${covfile}"
	runb2n="${b2ncmd} --genome_folder ${2} ${i}/${newbam} --dir ${repdir}"

	mbr="--mbias_report ${repdir}/${newbam::-4}.M-bias.txt"
	spr="--splitting_report ${repdir}/${newbam::-4}_splitting_report.txt"
	nur="--nucleotide_report ${repdir}/${newbam::-4}.nucleotide_stats.txt"
	alr="--alignment_report ${repdir}/${obamfile::-6}PE_report.txt"
	runb2r="${b2rcmd} ${mbr} ${spr} ${nur} ${ddr} ${alr} --dir ${repdir}"

	IFS=$'\n'
	#do the one with runsam to runsam, or without to not
	cmdlist=("$cprep" "$runsam" "$runbme" "$runc2c" "$runb2n" "$runb2r")
	for mycmd in ${cmdlist[@]}
	do
		IFS=" "
		echo -e "\e[41mI will run:\e[44m  ${mycmd}\e[0m"
		#if ${mycmd}; then
		#	echo "ran CMD without error:\n ${mycmd}" >> ${LOGFILE}
		#else
		#	echo "We died with this:\n ${mycmd}" >> ${LOGFILE}
		#	exit 1
		#fi
	done
done
exit 0
