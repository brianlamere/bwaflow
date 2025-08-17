#!/usr/bin/bash
#the intent of this is to be as absolutely readable/understable as possible
#put things readers will need to know, at the very top. 
#put things you *might* change, near the top.

#set to yes to send to stdout what would have been done, without running anything
dryrun="no"

#the $1 is the task you're running.
#references and targets are in sync for the current targets.
#references:  ADNP2  AJAP1  CELF5  EFNA3  EN1  LAMBDA  PAK6  PTPN2  SUZ12

curtime=$(date "+%d%h%Y-%H.%M.%S")
aroot="/projects/Toxo"
samcmd="/usr/bin/samtools"
mdcmd="/projects/usr/bin/MethylDackel"

#when you hit auto-complete tab it will have the trailing slash; remove if there
tgt=`echo ${1}|tr -d '/'`
#the next line will cause problems if there is more than 1 fasta file in that directory.
aref=`ls ${aroot}/references/${tgt}/*.fasta`

#manually sync the "-q " value to the mqX value
samVopts="view --threads 4 -q 42 --add-flags 0x2 -bT ${aref}"
mqX=".mq42" #manually sync with above -q value

samSopts="sort --threads 4"
samIopts="index --threads 4"
samSTopts="stats"
samFopts="faidx"
mdEopts="extract -@ 4"
mdCRopts="extract -@ 4 --cytosine_report" #if you tell it to do the reports, it can't bedgraph?
mdMCopts="mergeContext"
mdMBopts="mbias"

LOGFILE="./logfile.out"
[ -f $LOGFILE ] && mv $LOGFILE $LOGFILE.$curtime

samdir="/projects/Toxo/bwaout/${tgt}"
bamdir="/projects/Toxo/bamfiles/${tgt}"
[ ! -d ${bamdir} ] && mkdir -p ${bamdir}
repdir="/projects/Toxo/bwareports/${tgt}"
[ ! -d ${repdir} ] && mkdir -p ${repdir}

#this need only happen once...
runFsam="${samcmd} ${samFopts} ${aref}"
if ${runFsam}; then
       echo "ran CMD without error:\n ${runFsam}" >> ${LOGFILE}
else
       echo "We died with this:\n ${runFsam}" >> ${LOGFILE}
       exit 1
fi


for i in `ls -d ${tgt}/*${tgt}*|tr -s '//'`
do
	echo -e "\e[104m#### starting ${i} #########\e[0m" |tee -a $LOGFILE
	R1=`ls ${i}/*L001_R1_001.fastq.gz`
	IFS="/" read -ra parts1 <<< "$R1"
	uname="${parts1[1]}"
	samfile="${uname}.bwameth.sam"

	osamfull="${samdir}/${samfile}"
	newbam="${uname}${mqX}.bwameth.bam"
	nbamfull="${bamdir}/${newbam}"
	sortbam="${uname}${mqX}.sorted.bwameth.bam"
	sbamfull="${bamdir}/${sortbam}"
	statsfile="${repdir}/${uname}.bam.stats"
	idxstatsf="${repdir}/${uname}.bam.idxstats"

	#runVsam is the command to turn original .sam to a .bam with mapping quality filtering
	runVsam="${samcmd} ${samVopts} ${osamfull} -o ${nbamfull}"
	runSsam="${samcmd} ${samSopts} ${nbamfull} -o ${sbamfull}"
	runIsam="${samcmd} ${samIopts} ${sbamfull}"
	#damnit, it behaves differently when run manually.  samtools tries to parse the > for some reason.
	runSTsam="${samcmd} ${samSTopts} ${sbamfull} > ${statsfile}"
	mdpreF="${repdir}/${uname}" #if you don't do this it will go to bamdir
	runEmd="${mdcmd} ${mdEopts} ${aref} ${sbamfull} -o ${mdpreF}"
	runCRmd="${mdcmd} ${mdCRopts} ${aref} ${sbamfull} -o ${mdpreF}"
	runMCmd="${mdcmd} ${mdMCopts} ${aref} ${mdpreF}_CpG.bedGraph -o ${mdpreF}.mergeContext"
	runMBmd="${mdcmd} ${mdMBopts} ${aref} ${mdpreF}_CpG.bedGraph ${mdpreF}"
	#mbias is acting funny ha-ha, will ask if it's needed before figuring out why

	IFS=$'\n'
	#do the one with runsam to runsam, or without to not
	cmdlist=("$runVsam" "$runSsam" "$runIsam" "$runEmd" "$runCRmd" "$runMCmd")
	for mycmd in ${cmdlist[@]}
	do
		IFS=" "
		if [ "$dryrun" = "yes" ]; then
			echo "This is a dry run."
			echo -e "\e[41mI would run:\e[44m  ${mycmd}\e[0m"
		else
			echo -e "\e[41mI will run:\e[44m  ${mycmd}\e[0m"
			if ${mycmd}; then
				echo "ran CMD without error:\n ${mycmd}" >> ${LOGFILE}
			else
				echo "We died with this:\n ${mycmd}" >> ${LOGFILE}
				exit 1
			fi
		fi
	done
	if [ "$dryrun" = "yes" ]; then
		echo "Pocket commands won't be run"
	else
		#I hate this workaround, but whatever.
		echo "${runSTsam}" > /tmp/runSTsam.sh
		#echo "${runSTsam}"
		sh /tmp/runSTsam.sh
		rm /tmp/runSTsam.sh
	fi
done
exit 0
