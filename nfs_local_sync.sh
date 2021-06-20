#!/usr/bin/env bash
########################
# nfs_local_sync.sh
########################
# This script replicates files from `MOUNT_POINT` into 
# `RSYNC_DEST`.
# This attempts to accomplish the problem of if the NFS
# dies for any reason, we have a clone of the data.
#################################


set -e

MOUNT_POINT="/opt/nfs"
RSYNC_FLAGS="-rptAXEkd"
RSYNC_DEST="/home/ghost/nfs_reflect"


# Assert that the Network filesystem is mounted
data=$(findmnt -m "$MOUNT_POINT" | grep "$MOUNT_POINT")

if [ ${#data} -eq 0 ]; then
  echo "not mounted"
  exit 1
fi

rsync $RSYNC_FLAGS $MOUNT_POINT $RSYNC_DEST

