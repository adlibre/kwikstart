#!/bin/bash
#
# Install Redmine 1.4 w/ MySQL, Nginx (w/ Thin) on CentOS 6
#
# Assumes the host is clean unconfigured CentOS 6. Should be idempotent.
#
# Adlibre Pty Ltd 2012
#

## Configuration
SERVER_NAME=`hostname -d`
WWW_ROOT="/srv/www/${SERVER_NAME}"
USER='redmine'

## Constants
DB_USER='redmine'
DB_PASS=`tr -cd "[:alnum:]" < /dev/urandom | head -c 10` # 10 char random password
DB_NAME='redmine'
SERVERS=3
LOGFILE='install.log'

echo "### Beginning Install ###"

( # Start log capture

## Start
# Install EPEL Package Source if not Amazon AMI
if grep -qv Amazon /etc/system-release 2> /dev/null; then
    rpm -Uvh http://download.fedoraproject.org/pub/epel/6/$(uname -m)/epel-release-6-7.noarch.rpm
fi

# Install base packages
yum -y install nginx mysql-server ruby rubygem-rack rubygem-rake ruby-mysql subversion

# turn on services
chkconfig mysqld on
chkconfig nginx on

# Configure MySQL
service mysqld start
echo "CREATE DATABASE ${DB_NAME};" | mysql
echo "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" | mysql
echo "FLUSH PRIVILEGES;" | mysql

# Install Redmine from svn stable
mkdir -p ${WWW_ROOT}
adduser -d ${WWW_ROOT} -M ${USER}
cd ${WWW_ROOT}
svn co -q http://redmine.rubyforge.org/svn/branches/1.4-stable ./
# Dependent packages to build Redmine
yum -y install ruby-devel make gcc mysql-devel postgresql-devel ImageMagick-devel sqlite-devel
bundle install --without development test

# Configure redmine (as per doc/INSTALL)
cd ${WWW_ROOT}
cp config/configuration.yml.example config/configuration.yml # This will require customisation   

cat > config/database.yml << EOF
production:
  adapter: mysql
  database: ${DB_NAME}
  host: localhost
  username: ${DB_USER}
  password: ${DB_PASS}
  encoding: utf8
EOF

rake generate_session_store
rake db:migrate RAILS_ENV="production" # create database
# fix permissions
chown -R root:root ${WWW_ROOT}
chmod 755 ${WWW_ROOT}
mkdir -p public/plugin_assets # make missing dir
chown -R ${USER}:${USER} files log tmp public/plugin_assets
chmod -R 755 files log tmp public/plugin_assets

# Configure Nginx
cat > /etc/nginx/conf.d/redmine.conf << EOF
    # Redmine Configuration
    # From http://wiki.nginx.org/Redmine

    upstream redmine {
        server 127.0.0.1:8000;
        server 127.0.0.1:8001;
        server 127.0.0.1:8002;
    }

    server {
        server_name ${SERVER_NAME};
        root ${WWW_ROOT}/public;

        location / {
            try_files \$uri @ruby;
        }

        location @ruby {
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Host \$http_host;
            proxy_redirect off;
            proxy_read_timeout 300;
            proxy_pass http://redmine;
        }
    }
EOF

# Install & Configure Thin
yum -y install rubygem-thin
mkdir -p /etc/thin/
thin config -C /etc/thin/redmine.yml -c ${WWW_ROOT} --servers ${SERVERS} -e production -u ${USER} -g ${USER} -p 8000
thin install
chkconfig thin on

# Start
service thin start
service nginx start

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
