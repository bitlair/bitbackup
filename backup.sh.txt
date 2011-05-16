#!/bin/bash

# Copyright (C) Wilco Baan Hofman 2011
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA
#

SOURCES="/home /etc"
TARGET_USER=""
TARGET_HOST=""
TARGET_PATH="/backups/"
DAILY_MAX=7
WEEKLY_MAX=4
MONTHLY_MAX=3
ANNUALLY_MAX=2

NOTIFY_PEOPLE="user@domain.com"

# Execute a command on the remote host.
remote_cmd () {
        local CMD="$1"
        ssh "${TARGET_USER}"@"${TARGET_HOST}" "${CMD}"
}

rotate () {
        local DIRNAME="$1"
        local MAX="$2"

        echo "`date`: Rotating ${DIRNAME} directories.."

        # Clean up the oldest.
        remote_cmd "if [ -d \"${TARGET_PATH}/${DIRNAME}.${MAX}\" ];then \
                        chmod a+rwx -R \"${TARGET_PATH}/${DIRNAME}.${MAX}\"; \
                        rm -r \"${TARGET_PATH}/${DIRNAME}.${MAX}\"; \
                    fi"
        if [ "$?" -ne 0 ]; then
                return 2
        fi

        # Rotate directories.
        remote_cmd "for i in \$(seq $((${DAILY_MAX}-1)) -1 0);do \
                        if [ -d \"${TARGET_PATH}/${DIRNAME}.\$i\" ];then \
                                mv \"${TARGET_PATH}/${DIRNAME}.\$i\" \"${TARGET_PATH}/${DIRNAME}.\$((\$i+1))\"; \
                        fi \
                    done"
        if [ "$?" -ne 0 ]; then
                return 2
        fi

        return 0
}

do_backup () {
        local RET=0

        echo "`date`: Backing up ${SOURCES} .."
        echo "`date`: Target is ${TARGET_USER}@${TARGET_HOST}:${TARGET_PATH}.."

        # Rotate daily directories.
        rotate daily ${DAILY_MAX}
        local RV="$?"
        if [ "$RV" -ne 0 ];then
                return $RV
        fi

    # Hardlink files in daily.1 to daily.0
    remote_cmd "if [ -d \"${TARGET_PATH}/daily.1\" ]; then \
                    cp -al \"${TARGET_PATH}/daily.1\" \"${TARGET_PATH}/daily.0\"
                else
                    mkdir \"${TARGET_PATH}/daily.0\"
                fi"
    if [ "$RV" -ne 0 ];then
        return 2
    fi


        # Backup every directory in the sources list.
        for SOURCE in $SOURCES;do
                echo "`date`: Copying ${SOURCE}.."
                rsync --del -az --numeric-ids --relative --delete-excluded \
                -e ssh "${SOURCE}" '['"${TARGET_USER}"@"${TARGET_HOST}"']':"${TARGET_PATH}"/daily.0
                if [ "$?" -ne 0 ];then
                        RET=1
                fi
        done

        # Rotate weekly on sunday
        if [ "$(date +%u)" -eq 0 ];then
                rotate weekly ${WEEKLY_MAX}
                if [ "$?" -ne 0 ];then
                        local RET=2
                fi
                remote_cmd "cp -al \"${TARGET_PATH}/daily.0\" \"${TARGET_PATH}/weekly.0\""
                if [ "$?" -ne 0 ];then
                        local RET=2
                fi
        fi

        # Rotate monthly the first of every month
        if [ "$(date +%d)" -eq 1 ];then
                rotate monthly ${MONTHLY_MAX}
                if [ "$?" -ne 0 ];then
                        local RET=2
                fi
                remote_cmd "cp -al \"${TARGET_PATH}/daily.0\" \"${TARGET_PATH}/monthly.0\""
                if [ "$?" -ne 0 ];then
                        local RET=2
                fi
        fi

        # Rotate annually every Jan 1st
        if [ "$(date +%d)" -eq 1 -a "$(date +%m)" -eq 1 ];then
                rotate annually ${ANNUALLY_MAX}
                if [ "$?" -ne 0 ];then
                        local RET=2
                fi
                remote_cmd "cp -al \"${TARGET_PATH}/daily.0\" \"${TARGET_PATH}/annually.0\""
                if [ "$?" -ne 0 ];then
                        local RET=2
                fi
        fi

        return $RET
}

do_backup &> /tmp/backuplog-$$.txt
RV="$?"
if [ "$RV" -gt 1 ]; then
        SUBJECT="Backup: ERROR"
elif [ "$RV" -eq 1 ]; then
        SUBJECT="Backup: WARNING"
else
        SUBJECT="Backup: OK"
fi

for MAIL in $NOTIFY_PEOPLE;do
        cat /tmp/backuplog-$$.txt |mail -s "$SUBJECT" $MAIL
done
rm /tmp/backuplog-$$.txt
