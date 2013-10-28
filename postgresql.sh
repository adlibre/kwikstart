#!/bin/bash
#
# Setup PostgreSQL Server
#
# Assumes the host is clean unconfigured CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Adlibre Pty Ltd 2013
#

## Configuration

## Constants
LOGFILE='install.log'

echo "### Beginning Install ###"

( # Start log capture

## Start

if ! rpm -q pgdg-centos92 1> /dev/null; then
    rpm -ih --nosignature http://yum.pgrpms.org/9.2/redhat/rhel-$(egrep -oe '[0-9]' /etc/redhat-release | head -n1)-$(uname -m)/pgdg-centos92-9.2-6.noarch.rpm
fi

if ! rpm -q postgresql92-server  1> /dev/null; then
    yum -y install postgresql92-server
    # Create initial DB
    service postgresql-9.2 initdb
fi

# turn on services
chkconfig postgresql-9.2 on

# Start
service postgresql-9.2 start

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"