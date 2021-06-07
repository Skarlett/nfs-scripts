#!/usr/bin/env bash
########################
# nfs_local_sync.sh
########################
set -xe

SRC="/srv/nfs"
DEST_DIR="backups"
DROPS="dead_drops.lst"

TODAY=$(date -u --iso-8601)
DEST_NAME=$(date -u --iso-8601).tar.gz
SIGN_KEY="keys/signer/sign_key.pem"

AES_KEY=$(cat keys/encryption_key | hexdump -ve '/1 "%02x"')

####
# Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
compress() {
	local tmpFile=$(mktemp /tmp/backup.tar.gz.XXXXXXXXX)
	tar -cf "${tmpFile}" --exclude=".DS_Store" "${1}" || return 1
	size=$(
  	  stat -f"%z" "${tmpFile}" 2> /dev/null; # OS X `stat`
	  stat -c"%s" "${tmpFile}" 2> /dev/null # GNU `stat`
	)

	local cmd=""
	if (( size < 52428800 )) && hash zopfli 2> /dev/null; then
		# the .tar file is smaller than 50 MB and Zopfli is available; use it
		cmd="zopfli"
	else
		if hash pigz 2> /dev/null; then
			cmd="pigz"
		else
			cmd="gzip"
		fi
	fi

	echo "Compressing .tar using \`${cmd}\`…"
	"${cmd}" -v "${tmpFile}" || return 1
	mv "${tmpFile}.gz" "${2}"
}

#############
# Create archives
# Encrypt a copy of the archive 
create_backup() {
  # create archive
  mkdir "$DEST_DIR/clear/$TODAY" "$DEST_DIR/enc/$TODAY"
  compress "$SRC" "$DEST_DIR/clear/$TODAY/$DEST_NAME"

  # AES Block 256-bit cipher - 32 byte key - 16 byte iv
  # encrypt archive
  openssl enc -aes-256-cbc -in "$DEST_DIR/clear/$TODAY/$DEST_NAME" -out "$DEST_DIR/enc/$TODAY/$DEST_NAME.enc" -K $AES_KEY -iv $(head -c 16 /dev/urandom | hexdump -ve '/1 "%02x"')

  # in both encrypted & clear text
  for step in "$DEST_DIR/enc/$TODAY/$DEST_NAME.enc" "$DEST_DIR/clear/$TODAY/$DEST_NAME"; do
    # create signature from sha2
    openssl dgst -sha256 -sign $SIGN_KEY -out "$step.sha256" "$step"
    # Export as common file format (base64)
    openssl base64 -in "$step.sha256" -out "$step.signature.sha256"
    # remove original digest
    rm $step.sha256
  done
}

#######
# Upload encrypted archives to ssh-locations
sshdrop() {
  while read line; do
    key=$(echo $line | cut -d ' ' -f 2)
	host=$(echo $line | cut -d ' ' -f 1)
	echo "KEY $KEY"
	echo "HOST $HOST"
	[[ ${#line} -gt 0 ]] && rsync -az -e "ssh -i $(echo $line | cut -d ' ' -f 2)" $DEST_DIR/enc/$TODAY $(echo $line | cut -d ' ' -f 1)
  done < $DROPS;
}

main() {
  create_backup
  sshdrop
}

main
