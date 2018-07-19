#!/bin/bash

set -x

GLUSTERHOSTPREFIX=${1}
GLUSTERHOSTCOUNT=${2}
GLUSTERVOLUME=${3}

MOUNTPOINT=/mnt/${GLUSTERVOLUME}
mkdir -p ${MOUNTPOINT}

#Install Gluster Fuse Client

yum -y install psmisc

wget --no-cache https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-libs-4.1.1-1.el7.x86_64.rpm
rpm -i glusterfs-libs-4.1.1-1.el7.x86_64.rpm
wget --no-cache https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-4.1.1-1.el7.x86_64.rpm
rpm -i glusterfs-4.1.1-1.el7.x86_64.rpm
wget https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-client-xlators-4.1.1-1.el7.x86_64.rpm
rpm -i glusterfs-client-xlators-4.1.1-1.el7.x86_64.rpm
wget https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-fuse-4.1.1-1.el7.x86_64.rpm
rpm -i glusterfs-fuse-4.1.1-1.el7.x86_64.rpm

#Build list of servers

index=1
backupNodes="${GLUSTERHOSTPREFIX}${index}"
let index++
while [ $index -lt ${GLUSTERHOSTCOUNT} ] ; do
    backupNodes="${backupNodes}:${GLUSTERHOSTPREFIX}${index}"
    let index++
done

# Mount the file system and add the /etc/fstab setting

mount -t glusterfs -o backup-volfile-servers=${backupNodes} ${GLUSTERHOSTPREFIX}${GLUSTERHOSTCOUNT}:/${GLUSTERVOLUME} ${MOUNTPOINT}

LINE=${GLUSTERHOSTPREFIX}${GLUSTERHOSTCOUNT}:/${GLUSTERVOLUME}\t${MOUNTPOINT}\tglusterfs\tdefaults,backup-volfile-servers=${backupNodes}      0 0    
echo -e "${LINE}" >> /etc/fstab

# disable selinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/I' /etc/selinux/config
setenforce 0

