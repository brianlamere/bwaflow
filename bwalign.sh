#!/usr/bin/bash

#the $1 is the task you're running.  references and targets are in sync this time.
#references:  ADNP2  AJAP1  CELF5  EFNA3  EN1  LAMBDA  PAK6  PTPN2  SUZ12

curtime=$(date "+%d%h%Y-%H.%M.%S")

tgt=`echo ${1}|tr -d '/'`

aroot="/projects/toxo2"
aref=`ls ${aroot}/references/${tgt}/*.fasta`

bwa="python /usr/local/bin/bwameth.py"
bwargs="--threads 16 --reference ${aref}"
#previous bwargs="-L 25 -pCM -t 15"

LOGFILE="./logfile.out"
[ -f $LOGFILE ] && mv $LOGFILE $LOGFILE.$curtime

outdir="/projects/Toxo/bwaout/${tgt}"
[ ! -d ${outdir} ] && mkdir -p ${outdir}

#previous use had hundreds of items, still better to prevent typos however
for i in `ls -d ${tgt}/*${tgt}*|tr -s '//'`
do
	echo "starting $i" |tee -a $LOGFILE
	R1=`ls ${i}/*L001_R1_001.fastq.gz`
	R2=`ls ${i}/*L001_R2_001.fastq.gz`
	IFS="/" read -ra parts1 <<< "$R1"
	outfile="${parts1[1]}.bwameth.sam"

	outdir="/projects/Toxo/bwaout/${tgt}"
	perargs="${outdir}/${newdir}.bwameth.sam"
	outfull="${outdir}/${outfile}"
	bwacmd="${bwa} ${bwargs} ${aroot}/bsproj/${R1} ${aroot}/bsproj/${R2}"
	echo -e "\e[41mI will run:\e[44m  ${bwacmd} > ${outfull}\e[0m" | tee -a $LOGFILE
	if ${bwacmd} > ${outfull}; then
		echo "ran this without error:\n  ${bwacmd}" >> ${LOGFILE} 
	else
		echo "We died with this:\n ${bwacmd}\n.  If we die, we stop." | tee -a ${LOGFILE}
		exit 1
	fi
done

exit 0
