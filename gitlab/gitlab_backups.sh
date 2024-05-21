#!/bin/bash
#
# QUICK SCRIPT TO CREATE A GITLAB BACKUP SCRIPT
# AND ANOTHER SCRIPT TO MOVE THE BACKUP TO A 
# REMOTE NFS LOCATION, AND PLUGS IN CRON TASKS.
#
# WARNING: FIX VARIABLES IN REMOTE STORAGE SCRIPT
#          BEFORE RUNNING, OR JUST COPY OUT THE
#          PARTS YOU WANT.
#

#
# ----- GITLAB BACKUP SCRIPT -----
#

cat > /etc/cron.d/gitbak << "EOF"
#!/bin/bash

DS=$(date "+%Y%m%d")                  # DATE STAMP
BF=$(date "+%Y_%m_%d")                # BACKUP DATE FORMAT
BD=/root/gitbak/${DS}                 # LOCAL BACKUP DIRECTORY

mkdir -p ${BD}
cd ${BD}

gitlab-backup create

cp -a /var/opt/gitlab/backups/*${BF}* ./
cp -a /etc/gitlab/gitlab-secrets.json ./
cp -a /etc/gitlab/gitlab.rb ./

exit

EOF

#
# ----- GITLAB BACKUP REMOTE STORAGE SCRIPT -----
#

cat > /etc/cron.d/gitsto << "EOF"
#!/bin/bash

DS=$(date "+%Y%m%d")                  # DATE STAMP

KP="8"                                # BACKUPS TO KEEP
TD=mnttmp                             # TEMP MOUNT DIRECTORY

BD=/root/gitbak/                      # LOCAL BACKUP DIRECTORY
SM=/mnt/user/storage/backups          # STORAGE NFS MOUNT PATH
SB=${TD}/gitlab                       # STORAGE BACKUP DIRECTORY

cd ${BD}

mkdir -p ./${TD}
mount.nfs ${TD}:${SM} ./${TD}
sleep 1

mkdir -p ./${SB}
cp -uR ${DS} ./${SB}

    LIST=$(ls -rD1 "${SB}" | cut -f1 -d'/');
    cd "${SB}"
    i=1
    for t in ${LIST}; do
      if [ ${i} -gt "${KP}" ]; then
        printf "REMOVING OLD BACKUP: ${t}\n"
        rm -fR "${t}"
      fi
      i=$[$i+1]
    done
    cd "${BD}"

umount ./${TD}
sleep 1

rmdir ${TD}

exit

EOF

#
# ----- CRON TASKS -----
#

cat >> /etc/crontab << "EOF"

# GITLAB BACKUP (every sunday and thursday at 2am)
0 02 * * 0,4 root /root/cron.d/gitbak

# GITLAB BACKUP REMOTE STORAGE (every sunday and thursday at 3am)
0 03 * * 0,4 root /root/cron.d/gitsto

EOF

