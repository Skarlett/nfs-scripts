#!/usr/bin/env bash
###################
#
#
#########
set -xe

random-string() {
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-16} | head -n 1
}

_seq_mv() {
  if [ $(($# - 1)) -gt 0 ]; then
    local temp_dir=/tmp/rotate-backup.$(random-string)
    local args=( "${@}" )
    local next=0;

    if [ -d $2 ]; then
      mv $2 $temp_dir
      next=1
    fi

    mv $1 $2

    if [ $next -eq 1 ]; then
      _seq_mv $temp_dir "${args[@]:2}"
    fi
  fi
}

rotate_backups() {
  if [ ! -d ${@: -1} ]; then
    _seq_mv $@
  else
    echo "Usage: $0 new_1day/ 1day/ 2day/ 3day/ .. [non-existant dir]"
    echo "\tThis utility renames '1day/' into '2day/', and '2day/' into '3day/' and so forth"
    echo "\tNote: Any non-existant directory before the last argument causes this program to assume its the last entry"
    echo "$0: ERROR: last argument needs to be a non-existant directory name"
  fi
}

UPLOAD_DIR="/backup-target"
COLD_STORAGE="/cold-storage"
KEY="$COLD_STORAGE/signer.pem.pub"

process_new() {
  local today="$(date -u --iso-8601)"
  local filename="$today.tar.gz.enc"
  local signature="$filename.signature.sha256"

  # Already processed today
  if [[ -d "$COLD_STORAGE/1d/$today" ]]; then
    return -1;
  # No data available to process
  elif [[ ! -d "$UPLOAD_DIR/$today" ]]; then
    return -1;
  fi

  openssl base64 -d -in $UPLOAD_DIR/$today/$signature -out /tmp/$filename.sha256
  openssl dgst -sha256 -verify $KEY -signature /tmp/$filename.sha256 $UPLOAD_DIR/$today/$filename

  local verified=$?

  rm /tmp/$filename.sha256

  if [ verified -ne 0 ]; then
    echo "Bad signature, rejecting."
    rm $UPLOAD_DIR/*
    exit 3;
  fi

  new=$(mktemp -d $COLD_STORAGE/working_XXXXXXX)
  echo "moving $UPLOAD_DIR/$today/ to $new"
  mv $UPLOAD_DIR/$today $new

  # 1, 2, 3 day backups
  rotate_backups "$new" "$COLD_STORAGE/1d" "$COLD_STORAGE/2d" "$COLD_STORAGE/3d" "$COLD_STORAGE/4d"

  # 180d, 360d backups
  if [ -d "$COLD_STORE/before_180" && $(expr "$(date -u +'%s')" - "$(date -u -r $COLD_STORAGE/before_180 +'%s')") -gt 15552000 ]; then
    rotate_backups "$COLD_STORAGE/before_180" "$COLD_STORAGE/180d $COLD_STORAGE/360d" "$COLD_STORAGE/last"
  fi

  # 30d, 60d, 90d
  if [ -d "$COLD_STORAGE/before_30" && $(expr "$(date -u +'%s')" - "$(date -u -r $COLD_STORAGE/before_30 +'%s')") -gt 2592000 ]; then
    rotate_backups "$COLD_STORAGE/before_30" "$COLD_STORAGE/30d" "$COLD_STORAGE/60d" "$COLD_STORAGE/90d" "$COLD_STORAGE/before_180"
  fi

  # 1, 2, 4 week backups
  if [ ! -d "$COLD_STORAGE/before_7" ]; then
    mv $COLD_STORAGE/4d $COLD_STORAGE/before_7
  else
    if [[ $(expr "$(date -u +'%s')" - "$(date -u -r $COLD_STORAGE/before_7 +'%s')") -gt 604800 ]]; then
      rotate_backups $COLD_STORAGE/4d $COLD_STORAGE/before_7 $COLD_STORAGE/7d $COLD_STORAGE/14d $COLD_STORAGE/before_30
    else
      rm -rf $COLD_STORAGE/4d
    fi
  fi

  # Just in case anyone uploads anything else
  # outside what I expect.
  # eg malicious actor finds ssh key
  rm -rf $UPLOAD_DIR/* /tmp/$filename.sha256
  #touch $COLD_STORAGE/$BOOKMARKS/$today
  return 0;
}

main() {
  process_new
  [[ $? -eq "-1" ]] && rm -rf $UPLOAD_DIR/* /tmp/$filename.sha256
}
