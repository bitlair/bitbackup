#!/bin/bash
# IFCAT backup script
# Copyright (C) 2012 by Wilco Baan Hofman
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

SIGN_KEY=
ENCRYPT_KEY=
BACKUP_DIRLIST=
BACKUP_TARGET=
BACKUP_KEEP_CNT=
LVM_MOUNTS=
BACKUP_MAIL=
BACKUP_SUBJECT=


# Read the configuration
if [ "$1" = "" ]; then
	. /etc/backup.conf
else
	. $1
fi

# Fix the path to include system tools
export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin

# Define nasty error handlers
CHECK_RETURNVAL_WARN='RV=$?; [ "$RV" -gt "$RET" ] && echo WARNING && local RET=1'
CHECK_RETURNVAL_FAIL='RV=$?; [ "$RV" -gt "0" ] && echo FAILED && return 2'


function log {
	echo "$(date): $*"
}

function do_backup {
	local RET=0

	log "Starting backup ..."
	# Create and mount LVM snapshots with 1024MB max divergence
	if [ ! -d /media/backup-snapshots ]; then
		mkdir /media/backup-snapshots
	fi
	for LVM_MOUNT in $LVM_MOUNTS; do
		LVM_NAME="$(echo $LVM_MOUNT|cut -d: -f1)"
		LVM_DEV="$(echo $LVM_MOUNT|cut -d: -f2)"

		log "Snapshotting volume $LVM_NAME from $LVM_DEV ..."
		lvcreate -L1024M -s -n "$LVM_NAME" "$LVM_DEV"
		eval "$CHECK_RETURNVAL_FAIL"

		# Create the mountpoint and mount the snapshot
		if [ ! -d "/media/backup-snapshots/$LVM_NAME" ]; then
			mkdir "/media/backup-snapshots/$LVM_NAME"
		fi
		log "Mounting volume $LVM_NAME on /media/backup-snapshots/$LVM_NAME ..."
		mount "$LVM_DEV" "/media/backup-snapshots/$LVM_NAME"
		eval "$CHECK_RETURNVAL_FAIL"
	done

	# Prevents duplicity from asking for passwords
	export PASSPHRASE=

	# Remove all but x full backups, which in our case would be x months
	log "Cleaning up old backups..."
	duplicity remove-all-but-n-full $BACKUP_KEEP_CNT $BACKUP_TARGET
	eval $CHECK_RETURNVAL_WARN

	# Do a full backup on the first day of every month
	local FULL=
	if [ "$(date +%d)" = "01" ];then
		FULL="full"
		log "Doing a FULL backup..."
	fi

	local INCLUDE=
	for DIR in $BACKUP_DIRLIST; do
		local INCLUDE="$INCLUDE --include $DIR"
	done

	log "Starting the backup to $BACKUP_TARGET..."
	# Create an incremental backup of anything that takes time to replace
		
	ionice -n 7 -c 3 duplicity $FULL \
		--sign-key $SIGN_KEY --encrypt-key $ENCRYPT_KEY \
		$INCLUDE \
		--exclude '**' \
		/ $BACKUP_TARGET
	eval $CHECK_RETURNVAL_FAIL
	return $RET
}

function do_cleanup {
	local RET=0

	log "Cleaning up..."
	# Unmount and destroy the backup snapshots
	for LVM_MOUNT in $LVM_MOUNTS; do
		LVM_NAME="$(echo $LVM_MOUNT|cut -d: -f1)"
		LVM_DEV="$(echo $LVM_MOUNT|cut -d: -f2)"
		LVM_BASE="$(echo $LVM_DEV|cut -d/ -f 1-3)"

		umount "/media/backup-snapshots/$LVM_NAME"
		eval $CHECK_RETURNVAL_WARN

		lvremove -f "$LVM_BASE/$LVM_NAME"
		eval $CHECK_RETURNVAL_WARN
	done
	return $RET
}

function main {
	local RET=0

	# Perform backup and check the return value
	do_backup > /tmp/backuplog-$$.txt 2>&1
	local RET=$?

	# Clean up the backup 
	do_cleanup >> /tmp/backuplog-$$.txt 2>&1
	eval $CHECK_RETURNVAL_WARN

	case $RET in
	0)
		BACKUP_STATUS="OK"
		;;
	1)
		BACKUP_STATUS="WARNING"
		;;
	*)
		BACKUP_STATUS="FAILED"
		;;
	esac

	# Mail everybody!
	for MAIL in $BACKUP_MAIL; do
		cat /tmp/backuplog-$$.txt | mail -s "$BACKUP_SUBJECT: Backup $BACKUP_STATUS" "$MAIL"
	done

	rm /tmp/backuplog-$$.txt
}
main

