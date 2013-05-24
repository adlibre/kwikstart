#!/bin/bash
#
# Install Puppet or Puppet Master
#
# CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Adlibre Pty Ltd 2013
#

## Constants
LOGFILE='puppet-install.log'

# Additonal repos required for up to date puppet version
REPOFORGE="http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el6.rf.x86_64.rpm"
REPOCONF="/etc/yum.repos.d/rpmforge.repo"

# Git config for checkout on puppet master
GITREPO="git@bitbucket.org:adlibre/"
GITSSH=""
GITREPOPUB="bitbucket.org,207.223.240.181 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAubiN81eDcafrgMeLzaFPsw2kNvEcqTKl/VqLat/MaB33pZy0y3rJZtnqwR2qOOvbwKZYKiEO1O6VqNEBxKvJJelCq0dTXWT5pbO2gDXC6h6QDXCaHo6pOHGPUy+YBaGQRGuSusMEASYiWunYN0vCAI8QaXnWMXNMdFP3jHAJH0eDsoiGnLPBlBp4TNm6rYI74nMzgz3B9IikW4WVK+dc8KZJZWYjAuORU3jc1c/NPskD2ASinf8v3xnfXeukU0sJ5N6m5E8VLjObPEO+mN2t/FZTMZLiFqPWc/ALSqnMnnhwrNi2rbfg/rd/IpL8Le3pSBne8+seeFVBoGqzHM9yXw==
github.com,204.232.175.90 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="

function addpluginsync {
  sed -i '13 i\
    pluginsync = true' /etc/puppet/puppet.conf
}

echo "### Beginning Install ###"

( # Start log capture

# Check is rpmforge is already installed
if rpm -qa | egrep -q 'rpmforge'; then
  echo "rpmforge already installed. exiting"
  exit 1
fi

# Check is puppet or puppet-server is already installed
if rpm -qa | egrep -q '^puppet'; then 
  echo "Puppet already installed removing..." 
  yum -y remove puppet puppet-server
fi

# Install rpmforge repo
rpm -ivh ${REPOFORGE}

# Add priority and includepkgs to repo config
sed -i '/\[rpmforge\]/ a\
priority = 40 \
includepkgs = puppet puppet-server facter' ${REPOCONF}

# Install puppet or puppet master
if [ "${1}" == "master" ]; then
  # Install puppet-server and git
  yum -y install puppet-server git
  # Add git server pub key to known_hosts
  mkdir /root/.ssh
  chmod 700 /root/.ssh
  ${GITSSH} >> /root/.ssh/id_rsa
  echo "${GITREPOPUB}" >> /root/.ssh/known_hosts
  chmod 600 /root/.ssh/id_rsa
  chmod 600 /root/known_hosts
  # Move puppet config and checkout git repo
  mv /etc/puppet /tmp/puppet
  cd /etc
  git clone "${GITREPO}" puppet
  mv /tmp/puppet/* /etc/puppet/
  rm -rf /tmp/puppet
  # Add pluginsync to puppet.conf
  addpluginsync
  # Enable and start puppetmaster
  service puppetmaster start
  chkconfig puppetmaster on
else
  # Just install puppet client and add pluginsync
  yum -y install puppet
  addpluginsync
  # Add puppet cron task
  puppet apply -e "cron { 'puppet-agent': 
    ensure => present, 
    command => '/usr/bin/puppet agent --no-daemonize --onetime --splay > /dev/null 2>&1',
    minute => ['0','30'], 
    user => 'root' 
  }"
fi

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
