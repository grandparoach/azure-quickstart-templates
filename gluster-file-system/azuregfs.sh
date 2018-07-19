#!/bin/bash

# This script is only tested on CentOS 6.5
# You can customize variables such as MOUNTPOINT, RAIDCHUNKSIZE and so on to your needs.
# You can also customize it to work with other Linux flavours and versions.
# If you customize it, copy it to either Azure blob storage or Github so that Azure
# custom script Linux VM extension can access it, and specify its location in the 
# parameters of powershell script or runbook or Azure Resource Manager CRP template.   

set -x

NODENAME=$(hostname)
PEERNODEPREFIX=${1}
VOLUMENAME=${2}
NODEINDEX=${3}
NODECOUNT=${4}
PVSIZE=${5}

MOUNTPOINT="/datadrive"
RAIDCHUNKSIZE=128

VGNAME="rhgs-data"
LVNAME="brickpool"
LVPARTITION="brick1"

RAIDDISK="/dev/md127"
RAIDPARTITION="/dev/md127p1"
# An set of disks to ignore from partitioning and formatting
BLACKLIST="/dev/sda|/dev/sdb"

scan_for_new_disks() {
    # Looks for unpartitioned disks
    declare -a RET
    DEVS=($(ls -1 /dev/sd*|egrep -v "${BLACKLIST}"|egrep -v "[0-9]$"))
    for DEV in "${DEVS[@]}";
    do
        # Check each device if there is a "1" partition.  If not,
        # "assume" it is not partitioned.
        if [ ! -b ${DEV}1 ];
        then
            RET+="${DEV} "
        fi
    done
    echo "${RET}"
}

get_disk_count() {
    DISKCOUNT=0
    for DISK in "${DISKS[@]}";
    do 
        DISKCOUNT+=1
    done;
    echo "$DISKCOUNT"
}


create_raid0_centos() {
    echo "Creating raid0"
    yes | mdadm --create "$RAIDDISK" --name=data --level=0 --chunk="$RAIDCHUNKSIZE" --raid-devices="$DISKCOUNT" "${DISKS[@]}"
    mdadm --detail --verbose --scan > /etc/mdadm.conf
}

do_LVM_partition() {
    
    pvcreate --dataalignment 1024K ${1}
    vgcreate --physicalextentsize 256K ${VGNAME} ${1}
    lvcreate -L ${PVSIZE} -T ${VGNAME}/${LVNAME} -c 256K 
    lvchange --zero n ${VGNAME}/${LVNAME} 
    lvcreate -V ${PVSIZE} -T ${VGNAME}/${LVNAME} -n ${LVPARTITION} 
    

}



do_partition() {
# This function creates one (1) primary partition on the
# disk, using all available space
    DISK=${1}
    echo "Partitioning disk $DISK"
    echo "n
p
1


w
" | fdisk "${DISK}" 
#> /dev/null 2>&1

#
# Use the bash-specific $PIPESTATUS to ensure we get the correct exit code
# from fdisk and not from echo
if [ ${PIPESTATUS[1]} -ne 0 ];
then
    echo "An error occurred partitioning ${DISK}" >&2
    echo "I cannot continue" >&2
    exit 2
fi
}

add_to_fstab() {
    UUID=${1}
    MOUNTPOINT=${2}
    grep "${UUID}" /etc/fstab >/dev/null 2>&1
    if [ ${?} -eq 0 ];
    then
        echo "Not adding ${UUID} to fstab again (it's already there!)"
    else
        LINE="UUID=${UUID} ${MOUNTPOINT} ext4 defaults,noatime 0 0"
        echo -e "${LINE}" >> /etc/fstab
    fi
}

configure_disks() {
    ls "${MOUNTPOINT}"
    if [ ${?} -eq 0 ]
    then 
        return
    fi
    DISKS=($(scan_for_new_disks))
    echo "Disks are ${DISKS[@]}"
    declare -i DISKCOUNT
    DISKCOUNT=$(get_disk_count) 
    echo "Disk count is $DISKCOUNT"
    if [ $DISKCOUNT -gt 1 ];
    then
        
            create_raid0_centos
        
        do_LVM_partition ${RAIDDISK}
        PARTITION="/dev/${VGNAME}/${LVPARTITION}"
        
        #do_partition ${RAIDDISK}
        #PARTITION="${RAIDPARTITION}"
    else
        DISK="${DISKS[0]}"
        do_partition ${DISK}
        PARTITION=$(fdisk -l ${DISK}|grep -A 1 Device|tail -n 1|awk '{print $1}')
    fi

    echo "Creating filesystem on ${PARTITION}."
    mkfs.xfs -f -K -i size=512 -n size=8192 ${PARTITION}  
    #mkfs -t ext4 ${PARTITION}
    mkdir -p "${MOUNTPOINT}"

    #read UUID FS_TYPE < <(blkid -u filesystem ${PARTITION}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")
    #add_to_fstab "${UUID}" "${MOUNTPOINT}"
    echo -e "${PARTITION}\t${MOUNTPOINT}\txfs\tdefaults,inode64,nobarrier,noatime,nouuid 0 2"  | sudo tee -a /etc/fstab 
    
    echo "Mounting disk ${PARTITION} on ${MOUNTPOINT}"
    #mount "${MOUNTPOINT}"
    mount -a && mount 
}

open_ports() {
    firewall-cmd --zone=trusted --add-service=glusterfs --permanent
}


disable_selinux_centos() {
    sed -i 's/^SELINUX=.*/SELINUX=disabled/I' /etc/selinux/config
    setenforce 0
}

activate_secondnic_centos() {
    if [ -n "$SECONDNIC" ];
    then
        cp /etc/sysconfig/network-scripts/ifcfg-eth0 "/etc/sysconfig/network-scripts/ifcfg-${SECONDNIC}"
        sed -i "s/^DEVICE=.*/DEVICE=${SECONDNIC}/I" "/etc/sysconfig/network-scripts/ifcfg-${SECONDNIC}"
        defaultgw=$(ip route show |sed -n "s/^default via //p")
        declare -a gateway=(${defaultgw// / })
        sed -i "\$aGATEWAY=${gateway[0]}" /etc/sysconfig/network
        service network restart
    fi
}



configure_network() {
    open_ports
    
        activate_secondnic_centos
        disable_selinux_centos
    
}


install_glusterfs_centos() {
    yum list installed glusterfs-server
    if [ ${?} -eq 0 ];
    then
        return
    fi
    
    if [ ! -e /etc/yum.repos.d/epel.repo ];
    then
        echo "Installing extra packages for enterprise linux"
        wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        rpm -Uvh ./epel-release-latest-7*.rpm
        rm -f ./epel-release-latest-7*.rpm
        #yum -y update
    fi

    #yum -y install psmisc

    echo "installing gluster"
    #wget --no-cache https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-libs-4.1.1-1.el7.x86_64.rpm
    #rpm -i glusterfs-libs-4.1.1-1.el7.x86_64.rpm
    #wget --no-cache https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-4.1.1-1.el7.x86_64.rpm
    #rpm -i glusterfs-4.1.1-1.el7.x86_64.rpm
    #wget --no-cache https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-cli-4.1.1-1.el7.x86_64.rpm
    #rpm -i glusterfs-cli-4.1.1-1.el7.x86_64.rpm
    #wget --no-cache https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-client-xlators-4.1.1-1.el7.x86_64.rpm
    #rpm -i glusterfs-client-xlators-4.1.1-1.el7.x86_64.rpm
    #wget --no-cache https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-api-4.1.1-1.el7.x86_64.rpm
    #rpm -i glusterfs-api-4.1.1-1.el7.x86_64.rpm
    #wget --no-cache https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-fuse-4.1.1-1.el7.x86_64.rpm
    #rpm -i glusterfs-fuse-4.1.1-1.el7.x86_64.rpm
    #wget --no-cache https://buildlogs.centos.org/centos/7/storage/x86_64/gluster-4.1/glusterfs-server-4.1.1-1.el7.x86_64.rpm
    #rpm -i glusterfs-server-4.1.1-1.el7.x86_64.rpm
    
    yum -y install centos-release-gluster
    yum -y install  glusterfs-cli glusterfs-geo-replication glusterfs-fuse glusterfs-server glusterfs  
   
    #mv glusterfs-epel.repo  /etc/yum.repos.d/
    #yum -y update
    
    systemctl enable glusterd.service 
    systemctl enable glusterfsd.service 
    systemctl start glusterd.service 
    systemctl start glusterfsd.service 
    systemctl status glusterfsd.service 
    systemctl status glusterd.service 

}

configure_gluster() {
   
        /etc/init.d/glusterd status
        if [ ${?} -ne 0 ];
        then
            install_glusterfs_centos
        fi
        /etc/init.d/glusterd start        
    

    GLUSTERDIR="${MOUNTPOINT}/brick"
    ls "${GLUSTERDIR}"
    if [ ${?} -ne 0 ];
    then
        mkdir "${GLUSTERDIR}"
    fi

    if [ $NODEINDEX -lt $(($NODECOUNT)) ];
    then
        return
    fi
    
    allNodes="${NODENAME}:${GLUSTERDIR}"
    retry=10
    failed=1
    while [ $retry -gt 0 ] && [ $failed -gt 0 ]; do
        failed=0
        index=1
        echo retrying $retry >> /tmp/error
        while [ $index -lt $(($NODECOUNT)) ]; do
            ping -c 3 "${PEERNODEPREFIX}${index}" > /tmp/error
            gluster peer probe "${PEERNODEPREFIX}${index}" >> /tmp/error
            if [ ${?} -ne 0 ];
            then
                failed=1
                echo "gluster peer probe ${PEERNODEPREFIX}${index} failed"
            fi
            gluster peer status >> /tmp/error
            gluster peer status | grep "${PEERNODEPREFIX}${index}" >> /tmp/error
            if [ ${?} -ne 0 ];
            then
                failed=1
                echo "gluster peer status ${PEERNODEPREFIX}${index} failed"
            fi
            if [ $retry -eq 10 ]; then
                allNodes="${allNodes} ${PEERNODEPREFIX}${index}:${GLUSTERDIR}"
            fi
            let index++
        done
        sleep 30
        let retry--
    done

    gluster volume create ${VOLUMENAME} repl-vol replica 2 transport tcp ${allNodes} 2>> /tmp/error << EOF
y
EOF
    
    gluster volume info 2>> /tmp/error
    gluster volume start ${VOLUMENAME} 2>> /tmp/error

    #Tune for small file improvements
    gluster volume set ${VOLUMENAME} features.cache-invalidation on
    gluster volume set ${VOLUMENAME} features.cache-invalidation-timeout 600
    gluster volume set ${VOLUMENAME} performance.stat-prefetch on
    gluster volume set ${VOLUMENAME} performance.cache-samba-metadata on
    gluster volume set ${VOLUMENAME} performance.cache-invalidation on
    gluster volume set ${VOLUMENAME} performance.md-cache-timeout 600
    gluster volume set ${VOLUMENAME} network.inode-lru-limit: 90000

}

allow_passwordssh() {
    grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config
    if [ ${?} -eq 0 ];
    then
        return
    fi
    sed -i "s/^#PasswordAuthentication.*/PasswordAuthentication yes/I" /etc/ssh/sshd_config
    sed -i "s/^PasswordAuthentication no.*/PasswordAuthentication yes/I" /etc/ssh/sshd_config
    
        /etc/init.d/sshd reload
    
}



# temporary workaround form CRP 
allow_passwordssh  


    configure_network
    configure_disks
    configure_gluster

