#!/bin/bash
#
# Set hostname w/ puppet agent
#
# Assumes puppet install has already been run
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

# Check puppet is installed
if [ "`rpm -qa | grep puppet`" ]; then
  puppet agent --no-daemonize --onetime
  puppet apply -e "cron { 'puppet-agent':
    ensure => present,
    command => '/usr/bin/puppet agent --no-daemonize --onetime --splay > /dev/null 2>&1',
    minute => ['0','30'],
    user => 'root'
  }"
fi

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
