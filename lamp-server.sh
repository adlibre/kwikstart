#!/bin/bash
#
# Setup LAMP Server
#
# Assumes the host is clean unconfigured CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Adlibre Pty Ltd 2012
#

## Configuration
ROOT_PASS_FILE='/etc/mysql_root_password'
SERVER_NAME=`hostname -d`
WWW_ROOT="/srv/www/${SERVER_NAME}"
USER='wwwpub'

## Constants
LOGFILE='install.log'

echo "### Beginning Install ###"

( # Start log capture

## Start

# Set password if not already exist
if [ ! -f ${ROOT_PASS_FILE} ]; then
    DB_ROOT_PASS=`tr -cd "[:alnum:]" < /dev/urandom | head -c 10` # 10 char random password
    touch ${ROOT_PASS_FILE}
    chmod 600 ${ROOT_PASS_FILE}
    echo ${DB_ROOT_PASS} > ${ROOT_PASS_FILE}
    DB_ROOT_PASS_CURRENT=''
else
    DB_ROOT_PASS=`cat ${ROOT_PASS_FILE}`
    DB_ROOT_PASS_CURRENT=$DB_ROOT_PASS # Assume it was changed after install
fi

# Install base packages
yum -y install mysql-server
yum -y install php php-gd php-mcrypt php-pdo php-xml php-mysql httpd mod_ssl

# turn on services
chkconfig mysqld on
chkconfig httpd on

# Configure MySQL
service mysqld restart

# **sigh** http://bugs.mysql.com/bug.php?id=53796
yum -y install expect
# Use temp file for expect script (won't terminate when run from sub shell)
cat > /tmp/$$.expect << EOF
    spawn /usr/bin/mysql_secure_installation
    
    expect "Enter current password for root (enter for none):"
    send "${DB_ROOT_PASS_CURRENT}\r"

    expect -re "Set root password?|Change the root password?"
    send "Y\r"
    
    expect "New password:"
    send "${DB_ROOT_PASS}\r"
    
    expect "Re-enter new password:"
    send "${DB_ROOT_PASS}\r"
    
    expect "Remove anonymous users?"
    send "Y\r"
    
    expect "Disallow root login remotely?"
    send "Y\r"
    
    expect "Remove test database and access to it?"
    send "Y\r"
    
    expect "Reload privilege tables now?"
    send "Y\r"
    
    expect "Thanks for using MySQL!"
    puts "Ended expect script."
    expect eof
    exit
EOF
expect /tmp/$$.expect
rm -f /tmp/$$.expect

# Configure MySQL
cp -n /etc/my.cnf /etc/my.cnf.orig # backup

# TODO: This config needs some generalisation. And should configure it's size based on host memory setting.
cat > /etc/my.cnf << EOF
# The MySQL server configuration
[mysqld]
datadir = /var/lib/mysql
port = 3306
socket = /var/lib/mysql/mysql.sock
user = mysql
# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links = 0

key_buffer_size = 256M
max_allowed_packet = 8M
table_open_cache = 512
sort_buffer_size = 2M
read_buffer_size = 2M
read_rnd_buffer_size = 8M
myisam_sort_buffer_size = 64M
thread_cache_size = 8
query_cache_size = 32M

# Important if you have lots of tables
table_cache = 4096
table_definition_cache = 4096

[mysqld_safe]
log-error = /var/log/mysqld.log
pid-file = /var/run/mysqld/mysqld.pid
EOF

# Configure PHP
cp -n /etc/php.ini /etc/php.ini.orig # backup
sed -i -e "s@^short_open_tag.*@short_open_tag = On@g" /etc/php.ini # Some plugins need this
sed -i -e "s@^zlib.output_compression.*@zlib.output_compression = On@g" /etc/php.ini # Turn this off if Apache is handing compression
sed -i -e "s@^post_max_size.*@post_max_size = 32M@g" /etc/php.ini # Allow for 32M Upload
sed -i -e "s@^upload_max_filesize.*@upload_max_filesize = 32M@g" /etc/php.ini # Allow for 32M Upload

# Setup web root / site
mkdir -p ${WWW_ROOT}
adduser -d ${WWW_ROOT} -M ${USER}

# Configure Apache
cp -n /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.orig # backup
sed -i -e "s@^ServerTokens.*@ServerTokens Prod@g" /etc/httpd/conf/httpd.conf
sed -i -e "s@^KeepAlive Off@KeepAlive On@g" /etc/httpd/conf/httpd.conf
sed -i -e "s@^KeepAliveTimeout .*@KeepAliveTimeout 5@g" /etc/httpd/conf/httpd.conf
sed -i -e "s@^#NameVirtualHost \*:80@NameVirtualHost \*:80@g" /etc/httpd/conf/httpd.conf # enable name based vhosts

cat > /etc/httpd/conf.d/${SERVER_NAME}.conf << EOF
#
# ${SERVER_NAME}
#
<VirtualHost *:80>
        ServerAdmin   web-admin@${SERVER_NAME}
        ServerName    ${SERVER_NAME}

        DocumentRoot ${WWW_ROOT}

        # Add additional config here
        
</VirtualHost>
EOF

# Start / Restart
service mysqld restart
service httpd restart

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
