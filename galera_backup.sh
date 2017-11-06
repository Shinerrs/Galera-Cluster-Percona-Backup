#!/bin/bash

##############################################################################################
# Please install the following packages & repositories first                                 #
# rpm -Uhv http://www.percona.com/downloads/percona-release/percona-release-0.0-1.x86_64.rpm #
# qpress.x86_64 rsync.x86_64 percona-xtrabackup.x86_64                                       #
##############################################################################################

[ $(which qpress > /dev/null 2>&1; echo ${?}) -ne 0 ] && { echo -e "\nqpress is required...exiting"; exit 1; };
[ $(which rsync > /dev/null 2>&1; echo ${?}) -ne 0 ] && { echo -e "\nrsync is required...exiting"; exit 1; };
[ $(which innobackupex > /dev/null 2>&1; echo ${?}) -ne 0 ] && { echo -e "\npercona-xtrabackup is required...exiting"; exit 1; };

#set -x # Enable Debug
set -e  # stops execution if a variable is not set
set -u  # stop execution if something goes wrong

# Custom Variables
weeks=8;										# Number of weeks of backup's to keep
backupDirectory=/home/backup/galera_cluster;						# Backup Directory
dataDirectory=/var/lib/mysql;								# MySQL Database Location
userArguments="--user=root --password=PaSsWoRd --socket=/var/lib/mysql/mysql.sock";	# MySQL Username & Password

usage() {
	echo -e "\nusage: $(dirname $0)/$(basename $0) {full|incremental|restore|help}";
	echo;
	echo -e "full:\t\tCreate a full backup of Galera Cluster /var/lib/mysql using innobackupex.";
	echo -e "incremental:\tCreate an incremental backup";
	echo -e "restore:\tRestore the latest backup to Galera Cluster, BE CAREFUL!";
	echo -e "help:\t\tShow this help";
}

full() {
	date;
	if [ ! -d ${backupDirectory} ]; then
		echo "ERROR: the folder ${backupDirectory} does not exists";
		exit 1;
	fi;
	echo "doing full backup...";
	echo "cleaning the backup folder...";
	if [ ${weeks} -gt 1 ]; then
		[ -d "${backupDirectory}/${weeks}" ] && rm -fr ${backupDirectory}/${weeks};
		for (( i = ${weeks}; i > 1; i-- ))
		{
			[ -d "${backupDirectory}/$((${i} - 1))" ] && mv -f ${backupDirectory}/$((${i} - 1)) ${backupDirectory}/${i};
		}
		mkdir -p ${backupDirectory}/1;
	fi;
	echo "cleaning done!";
#	innobackupex  --no-lock --parallel=4  --user=root  --extra-lsndir=/usr/local/src/incremental_last_checkpoint/  --no-timestamp /usr/local/src/fullbackup
	innobackupex ${ARGS} ${backupDirectory}/1/FULL;
	date;
	echo "backup done!";
}

incremental() {
	if [ ! -d ${backupDirectory}/1/FULL ]; then
		echo "ERROR: no full backup has been done before. aborting";
		exit -1;
	fi;

	#we need the incremental number
	if [ ! -f ${backupDirectory}/1/last_incremental_number ]; then
		NUMBER=1;
	else
		NUMBER=$(($(cat ${backupDirectory}/1/last_incremental_number) + 1));
	fi;
	date;
	echo "doing incremental number ${NUMBER}";
	if [ ${NUMBER} -eq 1 ]; then
		innobackupex ${ARGS} --incremental ${backupDirectory}/1/inc${NUMBER} --incremental-basedir=${backupDirectory}/1/FULL;
	else
		innobackupex ${ARGS} --incremental ${backupDirectory}/1/inc${NUMBER} --incremental-basedir=${backupDirectory}/1/inc$((${NUMBER} - 1));
	fi;
	date;
	echo ${NUMBER} > ${backupDirectory}/1/last_incremental_number;
	echo "incremental ${NUMBER} done!";
}

restore() {
	[ `pidof -x mysqld > /dev/null 2>&1; echo ${?}` -eq 0 ] && ( echo "MySQL Daemon is currently running, stop the mysqld service & try again..."; exit 1; );
	echo "WARNING: are you sure this is what you want to do? (Enter 1 or 2)";
	select yn in "Yes" "No"; do
		case $yn in
			Yes )
				break
			;;
			No )
				echo "aborting...";
				exit;
			;;
		esac
	done;

	# Full backup Preparation
	echo "Uncompressing the Full backups files...";
	for bf in `find ${backupDirectory}/1/FULL -iname "*\.qp"`; do qpress -d ${bf} $(dirname ${bf}); echo "processing" ${bf}; rm ${bf}; done;
	date;
	echo "uncompressing done!, preparing the backup for restore...";
	innobackupex --apply-log --use-memory=1G --redo-only ${backupDirectory}/1/FULL;
	date;
	echo "preparation done!";

	# Incremental backup Preparation
	echo "Uncompressing the incremental backups files...";
	for ((NUMBER=1; NUMBER <= `cat ${backupDirectory}/1/last_incremental_number` ; NUMBER++)); do
		for bf in `find ${backupDirectory}/1/inc${NUMBER} -iname "*\.qp"`; do qpress -d ${bf} $(dirname ${bf}) ;echo "processing" ${bf}; rm ${bf}; done;
	done;
	date;
	echo "uncompressing done!, the preparation will be made when the restore is needed";

	date;
	echo "doing restore...";
	#innobackupex --apply-log --use-memory=1G --redo-only ${backupDirectory}/1/FULL

	# Appending all the increments
	P=1;
	while [ -d ${backupDirectory}/1/inc${P} ] && [ -d ${backupDirectory}/1/inc$((${P}+1)) ]; do
		echo "processing incremental ${P}";
		innobackupex --apply-log --use-memory=1G --redo-only ${backupDirectory}/1/FULL --incremental-dir=${backupDirectory}/1/inc${P};
		P=$((${P}+1));
	done;

	if [ -d ${backupDirectory}/1/inc${P} ]; then
		#the last incremental has to be applied without the redo-only flag
		echo "processing last incremental ${P}";
		innobackupex --apply-log --use-memory=1G $backupDirectory/1/FULL --incremental-dir=$backupDirectory/1/inc${P};
	fi;

	# Preparing the full backup
	innobackupex --apply-log --use-memory=1G ${backupDirectory}/1/FULL;

	#finally we copy the folder
	cp -r ${dataDirectory} ${dataDirectory}.back;
	rm -rf ${dataDirectory}/*;
	innobackupex --copy-back ${backupDirectory}/1/FULL;

	chown -R mysql:mysql ${dataDirectory};
}

#######################################
#######################################
#######################################

ARGS="--rsync $userArguments --no-lock --parallel=4 --no-timestamp --compress --compress-threads=4";

[ ! -d "${backupDirectory}" ] && mkdir -p ${backupDirectory};

if [ $# -eq 0 ]; then
	usage;
	exit 1;
fi;

case $1 in
	"full")
		full;
	;;
	"incremental")
		incremental;
	;;
	"restore")
		restore;
	;;
	"help")
		usage;
	;;
	*)
		echo "invalid option";
	;;
esac
