#!/bin/bash
#
# Set hostname
#
# CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Adlibre Pty Ltd 2013
#

## Configuration
HOST_FQDN=$1
HOST_SHORT=`echo $HOST_FQDN |awk -F. '{ print $1 }'`
IPADDR=$(/sbin/ifconfig eth0) ; IPADDR=${IPADDR/*inet addr:/} IPADDR=${IPADDR/ */}

## Constants
LOGFILE='install.log'

echo "### Beginning Install ###"

( # Start log capture

# If not already exists 
if [ -z ${HOST_FQDN} ]; then
    echo "Hostname not set. Usage: ./set-hostname.sh <hostname>"
    exit
fi

sed -i -e "s@^HOSTNAME=.*\$@HOSTNAME=${HOST_FQDN}@" /etc/sysconfig/network
echo "${IPADDR} ${HOST_FQDN} ${HOST_SHORT}" >> /etc/hosts
hostname ${HOST_FQDN}

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
