#!/bin/bash
#
# Generate CSR / Server Key
#
# CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Adlibre Pty Ltd 2013
#

## Configuration
DOMAIN_NAME=`hostname -d`
KEY_SIZE='2048'

## Constants
LOGFILE='install.log'
SERVER_KEY="/etc/pki/tls/private/${DOMAIN_NAME}.key"
CSR_FILE="/etc/pki/tls/certs/${DOMAIN_NAME}.csr"

echo "### Beginning Install ###"

( # Start log capture

## Start

# If not already exists 
if [ ! -f ${SERVER_KEY} ]; then
    openssl genrsa -out ${SERVER_KEY} ${KEY_SIZE} && chmod 600 ${SERVER_KEY}
else
    echo "Server Key Exists"
fi

openssl req -new -key ${SERVER_KEY} -out ${CSR_FILE}

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
