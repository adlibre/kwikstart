#!/bin/bash
#
# Install Nginx (without a site config or php reqs)
#
# Assumes the host is clean unconfigured CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Adlibre Pty Ltd 2013
#

## Configuration
WWW_ROOT="/srv/www/"

## Constants
LOGFILE='install.log'

echo "### Beginning Install ###"

( # Start log capture

## Start
# Install EPEL Package Source if not Amazon AMI
if grep -qv Amazon /etc/system-release 2> /dev/null; then
    rpm -Uvh http://download.fedoraproject.org/pub/epel/6/$(uname -m)/epel-release-6-8.noarch.rpm
fi

# Install Nginx Repo
cat > /etc/yum.repos.d/nginx.repo << EOF
[nginx]
name=Nginx Official Repository
baseurl=http://nginx.org/packages/$(awk '{print tolower($1)}' < /etc/redhat-release)/6/\$basearch/
gpgcheck=0
enabled=1
EOF

# Install base packages
yum -y install nginx

mkdir -p ${WWW_ROOT}

# turn on services
chkconfig nginx on

# Start / Restart
service nginx restart

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
