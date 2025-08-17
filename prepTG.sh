#!/usr/bin/bash
#set -e

#21Mar2025 - this is very specific to a particular set of basespace/illumina files
#in this particular dataset there were only 2fastq files each dir, an R1 and R2
#just learned about nextflow today; likely will install that and start using it...
# ...after this run.

#the first arg is the directory with the subdirectories. this is what is being aligned 

aroot="/projects/basespace/val_Methylation_PIRCPBMC_Lambda/"
scratch="/projects/scratch"
curtime=$(date "+%d%h%Y-%H.%M.%S")
tgf="/usr/local/bin/trim_galore"
#adargs="-a CTGTCTCTTATACACATCT"
#adargs="-a GGGGTGATTTTATTTTTNGGGGTTG"
#adargs='-a " CTGTCTCTTATACACATCT -a GGGGTGATTTTATTTTTYGGGGTTG -n 2"'
#adargs='-a "file:./TNF1B_filter.fa"'

othargs="-j 12 --paired --length 50"

if [ ! -d $aroot/ ]; then
	echo "the $aroot directory didn't even exist.  You're failing early."
	exit 1
fi

LOGFILE="./logfile.out"

[ -f $LOGFILE ] && mv $LOGFILE $LOGFILE.$curtime

for i in `ls -d $1/MS*|tr -s '//'`
do
	echo "for $i we have:" >> $LOGFILE
	echo "running for $i"
	#this will stay clunky since it is for a particular set of data
	#a simple wc of the output would be a great error catch btw
	R1=`ls $i/*L001_R1_001.fastq`
	R2=`ls $i/*L001_R2_001.fastq`
	        IFS="/" read -ra parts1 <<< "$R1"
        IFS="_" read -ra parts2 <<< "${parts1[2]}"
        echo "for3 we made ${parts2[@]}" >> $LOGFILE
        if [[ ${#parts2[@]} == "7" ]]; then
                runname="${2}_${parts2[0]:8}_${parts2[1]}"
        else
                runname="${2}_${parts2[0]:8}"
        fi
	tgcmd="${tgf} ${othargs} -o ${aroot}/${runname} ${adargs} ${R1} ${R2}"
	echo -e "\e[41mI would run:\e[44m ${tgcmd}\e[0m"
	[ -d ${aroot}/${runname} ] || mkdir -p ${aroot}/${runname}
	if ${tgcmd}; then
		echo "ran this without error:\\n $tgcmd" >> $LOGFILE 
	else
		echo "We died with this: ${tgcmd} \\n  If we die, we stop." | tee -a $LOGFILE
		exit 1
	fi
done

