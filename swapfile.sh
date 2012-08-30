#!/bin/bash
#
# Add file backed swap
#
# CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Adlibre Pty Ltd 2012
#

## Configuration
SWAP_SIZE='512' # in MB
SWAP_FILE='/.swapfile'

## Constants
LOGFILE='install.log'

echo "### Beginning Install ###"

( # Start log capture

## Start

# If already exists allow us to resize.
if [ ! -f ${SWAP_FILE} ]; then
    echo "${SWAP_FILE}              swap                    swap    defaults        0 0" >> /etc/fstab
    touch ${SWAP_FILE}
else
    swapoff ${SWAP_FILE}
fi

# Create / Recreate swap file
chmod 600 ${SWAP_FILE}
dd if=/dev/zero of=${SWAP_FILE} bs=1M count=${SWAP_SIZE}
mkswap ${SWAP_FILE}
swapon ${SWAP_FILE}

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
