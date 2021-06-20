#!/usr/bin/env bash
set -e

TARGET="/srv/nfs"
MTIMEGT=604800 # 7 days

./prune_nfs.pl -c junk.yml -d $TARGET -mtimegt $MTIMEGT
./prune_nfs.pl -a config.yml -d $TARGET -mtimegt $MTIMEGT --archive 