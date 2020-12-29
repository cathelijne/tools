#!/bin/bash

# Backup script for web servers
# Backs up select directories and installed gems, packages, python modules
# Dumps mysql databases that are accessible by a "backup" user (it needs to exist)
# Makes a backup every day, and keeps 7 daily, 4 weekly and 12 monthly backups
# quite rudimentary, and needs quite a lot of space, but it works.

# Settings
BACKUPDIR="/backup"
FTPHOST="some.host"
FTPUSER="user"
FTPPASS="pass"
MYSQLUSER="backup"
MYSQLPASS="pass"

# What to backup
BACKUP=(
/etc/
/var/www/
/root/
/usr/local/bin/
)

# we also make backups of installed packages, gems, python midules and make a mysqldump


# Date magic
TODAY=`date +%Y%m%d`
TOMORROW=`date +%d --date "+1 days"`
DOW=`date +%u`
MOY=`date +%m`
DOM=`date +%d`

MESSAGE="Backup results for ${TODAY}:\n\n"

# Rotate 4 weekly backups on Sundays
if [ "${DOW}" -eq "7" ]; then
	MESSAGE="${MESSAGE}It's Sunday. Rotating the weekly backups...\n"
	rm -rf ${BACKUPDIR}/weekly/4 && MESSAGE="${MESSAGE}Deleting oldest backup...\n" || MESSAGE="${MESSAGE}Oops "
	mv ${BACKUPDIR}/weekly/3 ${BACKUPDIR}/weekly/4 && MESSAGE="${MESSAGE}Moving backups around... 3 -> 4..."  || MESSAGE="${MESSAGE}Oops "
	mv ${BACKUPDIR}/weekly/2 ${BACKUPDIR}/weekly/3 && MESSAGE="${MESSAGE} 2 -> 3..."  || MESSAGE="${MESSAGE}Oops "
	mv ${BACKUPDIR}/weekly/1 ${BACKUPDIR}/weekly/2 && MESSAGE="${MESSAGE} 1 -> 2..."  || MESSAGE="${MESSAGE}Oops "
	mv ${BACKUPDIR}/daily/7 ${BACKUPDIR}/weekly/1 && MESSAGE="${MESSAGE} last week -> 1...\n"  || MESSAGE="${MESSAGE}Oops\n"
	mkdir ${BACKUPDIR}/daily/7 && MESSAGE="${MESSAGE}New backupdir created\n"  || MESSAGE="${MESSAGE}Oops\n"
	MESSAGE="${MESSAGE}Done rotating backups\n"
fi

# Make the backup
TODAYSBACKUP="${BACKUPDIR}/daily/${DOW}"

if [ ! -d ${TODAYSBACKUP} ]; then
	mkdir -p ${TODAYSBACKUP}  && MESSAGE="${MESSAGE}Created ${TODAYSBACKUP}\n"  || MESSAGE="${MESSAGE}Oops\n"
else
	rm -rf ${TODAYSBACKUP}/*
fi

for i in ${BACKUP[@]}; do
	#NAME=`basename $i`
	NAME=`echo $i |tr "/" "-"`
	tar czf ${TODAYSBACKUP}/${TODAY}${NAME}.tar.gz --exclude cache/ --exclude 'FICC Youth Rally day *' --exclude '.pdepend/' $i && MESSAGE="${MESSAGE}Backed up ${i} "  || MESSAGE="${MESSAGE}Oops (${i}\n"
        MESSAGE="${MESSAGE}(size: $(ls -lh ${TODAYSBACKUP}/${TODAY}${NAME}.tar.gz |awk '{print $5}'))\n"
done

# See what packages, gems and python modules are installed and back up
/usr/bin/mysqldump -u${MYSQLUSER} -p${MYSQLPASS} --all-databases --ignore-table=mysql.events > ${TODAYSBACKUP}/${TODAY}.sql \
	 && MESSAGE="${MESSAGE}Backed up mysql\n"  || MESSAGE="${MESSAGE}Oops (mysql)\n"
# debian based systems
#/usr/bin/dpkg --get-selections > ${TODAYSBACKUP}/${TODAY}.selections \
#	 && MESSAGE="${MESSAGE}Backed up installed packages\n"  || MESSAGE="${MESSAGE}Oops (dpkg --get-selections)\n"
# redhat based systems
rpm -qa > ${TODAYSBACKUP}/${TODAY}.rpmlist \
	 && MESSAGE="${MESSAGE}Backed up installed packages\n"  || MESSAGE="${MESSAGE}Oops (rpm -qa)\n"
if [ -f /usr/bin/gem ]; then
	/usr/bin/gem list > ${TODAYSBACKUP}/${TODAY}.gems \
	&& MESSAGE="${MESSAGE}Backed up installed gems\n"  || MESSAGE="${MESSAGE}Oops (gem list)\n"
fi
if [ -f /usr/bin/pip ]; then
	/usr/bin/pip list > ${TODAYSBACKUP}/${TODAY}.pip \
	&& MESSAGE="${MESSAGE}Backed up installed PyPi\n"  || MESSAGE="${MESSAGE}Oops (PyPi)\n"
fi

# If it's the last day of the month, copy it to the monthly dir
if [ "${TOMORROW}" -eq "1" ]; then
	MESSAGE="${MESSAGE}Last day of the month. Saving an extra copy of our backup..."
	rm -rf ${BACKUPDIR}/monthly/${MOY} || MESSAGE="${MESSAGE}Oops (rm last year's backup)\n"
	cp -a ${TODAYSBACKUP} ${BACKUPDIR}/monthly/${MOY} && MESSAGE="${MESSAGE}done.\n"  || MESSAGE="${MESSAGE}Oops (copy backup)\n"
fi


# Upload to our backupserver
/usr/bin/lftp -e 'set ssl:verify-certificate no; \
	set ftp:passive-mode true; \
	set net:timeout 10; \
	mirror -Rv \
	--only-newer \
	--delete \
	/backup/ /backup/; \
	bye' \
	-u ${FTPUSER},${FTPPASS} ${FTPHOST} \
	 && MESSAGE="${MESSAGE}\nBackup uploaded, all set.\n"  || MESSAGE="${MESSAGE}Oops (upload backup)\n"

# Slack it!
PAYLOAD='{"text": "'$MESSAGE'", "username": "backupbot", "icon_emoji": ":floppy_disk:"}'
/usr/bin/curl -X POST --data-urlencode "payload=$PAYLOAD" https://hooks.slack.com/services/yourslackhook