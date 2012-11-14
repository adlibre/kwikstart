#!/bin/bash
#
# Setup Lighttpd w/ APC for Wordpress
#
# Assumes the host is clean unconfigured CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Adlibre Pty Ltd 2012
#

## Configuration
WWW_ROOT='/srv/www'
SERVER_NAME=`hostname`
APC_SHM_SIZE='256M'
# APC: use 0, 600, 600 to flush cache in case of APC memory exhaustion (prevents fragmentation too) 
APC_TTL=0 
APC_USER_TTL=600
APC_GC_TTL=600
PHP_FCGI_CHILDREN=8
PHP_FCGI_MAX_REQUESTS=1000

## Constants
LOGFILE='install.log'

echo "### Beginning Install ###"

( # Start log capture

## Start
# Install EPEL Package Source if not Amazon AMI
if grep -qv Amazon /etc/system-release 2> /dev/null; then
    rpm -Uvh http://download.fedoraproject.org/pub/epel/6/$(uname -m)/epel-release-6-7.noarch.rpm
fi

# Install base packages
yum -y install lighttpd lighttpd-fastcgi php php-mysql php-gd php-xml php-pecl-apc

# Configure Lighttpd Permissions
mkdir -p /var/cache/lighttpd/compress /var/run/lighttpd
chown -R lighttpd:lighttpd /var/cache/lighttpd/ /var/run/lighttpd
chown root:lighttpd /var/lib/php/session/
mkdir -p ${WWW_ROOT}

# turn on services
chkconfig lighttpd on

# Configure Lighttpd base config
cp -n /etc/lighttpd/modules.conf /etc/lighttpd/modules.conf.orig # backup
cp -n /etc/lighttpd/lighttpd.conf /etc/lighttpd/lighttpd.conf.orig # backup

# enable lighttpd modules
sed -i -e 's@#  "mod_alias",@  "mod_alias",@g' /etc/lighttpd/modules.conf
sed -i -e 's@#  "mod_redirect",@  "mod_redirect",@g' /etc/lighttpd/modules.conf
sed -i -e 's@#  "mod_rewrite",@  "mod_rewrite",@g' /etc/lighttpd/modules.conf
# enable lighttpd features
sed -i -e 's@#include "conf.d/compress.conf"@include "conf.d/compress.conf"@g' /etc/lighttpd/modules.conf
sed -i -e 's@#include "conf.d/fastcgi.conf"@include "conf.d/fastcgi.conf"@g' /etc/lighttpd/modules.conf
sed -i -e 's@#include "conf.d/expire.conf"@include "conf.d/expire.conf"@g' /etc/lighttpd/modules.conf
# enable vhost includes
sed -i -e 's@#include_shell "cat /etc/lighttpd/vhosts.d/\*.conf"@include_shell "cat /etc/lighttpd/vhosts.d/\*.conf"@g' /etc/lighttpd/lighttpd.conf

# Configure Lighttpd vhost
cat > /etc/lighttpd/vhosts.d/${SERVER_NAME}-wordpress.conf << EOF
    # Wordpress Lighttpd Config for ${SERVER_NAME}
    
    # Redirect naked domain to www
    \$HTTP["host"] != "^(www.${SERVER_NAME})" {
        url.redirect = ( "^/(.*)" => "http://www.${SERVER_NAME}/\$1" )
    }
    
    \$HTTP["host"] =~ "^www.${SERVER_NAME}" {
        
        server.name = "${SERVER_NAME}"
        server.document-root = "${WWW_ROOT}"
        
        # PHP FCGI Server
        fastcgi.server = ( ".php" =>
            ( "php" =>
                (
                    "socket" => "/var/run/lighttpd/lighttpd-fastcgi-php.socket",
                    "bin-path" => "/usr/bin/php-cgi",
                    "bin-environment" => (
                        "PHP_FCGI_CHILDREN" => "${PHP_FCGI_CHILDREN}",
                        "PHP_FCGI_MAX_REQUESTS" => "${PHP_FCGI_MAX_REQUESTS}",
                    ),
                    "max-procs" => 1,
                    "broken-scriptfilename" => "enable",
                )
            ),
        )
        
        # Send Requests to appropriate handler
        url.rewrite-if-not-file = (
            #
            # Wordpress Standard Rewrites
            #
            
            # Exclude some directories from rewriting
            "^/(wp-admin|wp-includes|wp-content)(.*)" => "\$0",
            
            # Pass all to handler
            "^/(.*)$" => "/index.php/\$1"
        )
        
        # Compress output by type
        compress.filetype = ("application/x-javascript", "application/javascript", "text/javascript", "text/x-js", "text/css", "text/html", "text/plain")
        
        # Allow caching of static assets
        expire.url = (
            "^(wp-includes|wp-content)/(.*)" => "access 7 days",
            "^(.*).(js|css|png|jpg|jpeg|gif|ico|mp3|flv)" => "access 7 days",
        )
        
        server.error-handler-404 = "/index.php"
    }
EOF

# Configure PHP
cp -n /etc/php.ini /etc/php.ini.orig # backup
sed -i -e "s@^short_open_tag.*@short_open_tag = On@g" /etc/php.ini # Some plugins need this
sed -i -e "s@^zlib.output_compression.*@zlib.output_compression = Off@g" /etc/php.ini # Turn this off if W3 Total Cache / Lighttpd is handing compression
sed -i -e "s@^post_max_size.*@post_max_size = 32M@g" /etc/php.ini # Allow for 32M Upload
sed -i -e "s@^upload_max_filesize.*@upload_max_filesize = 32M@g" /etc/php.ini # Allow for 32M Upload

# Configure APC
cp -n /etc/php.d/apc.ini /etc/php.d/apc.ini.orig # backup
sed -i -e "s@^apc.shm_size=.*@apc.shm_size=${APC_SHM_SIZE}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.ttl=.*@apc.ttl=${APC_TTL}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.user_ttl=.*@apc.user_ttl=${APC_USER_TTL}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.gc_ttl=.*@apc.gc_ttl=${APC_GC_TTL}@g" /etc/php.d/apc.ini

# Start / Restart
service lighttpd restart

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
