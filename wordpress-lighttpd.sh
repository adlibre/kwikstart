#!/bin/bash
#
# Setup Lighttpd w/ APC for Wordpress
#
# Assumes the host is clean unconfigured CentOS 6 / EL 6 derivatives. Should be idempotent.
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

# Install base packages
yum -y install lighttpd-fastcgi php php-mysql php-gd php-xml php-pecl-apc

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
# enable vhost includes
sed -i -e 's@#include_shell "cat /etc/lighttpd/vhosts.d/*.conf"@include_shell "cat /etc/lighttpd/vhosts.d/*.conf"@g' /etc/lighttpd/lighttpd.conf

# Configure Lighttpd vhost
cat > //etc/lighttpd/vhosts.d/${SERVER_NAME}-wordpress.conf << EOF
    # Wordpress Lighttpd Config for ${SERVER_NAME}
    
    # Redirect naked domain to www
    $HTTP["host"] != "^(www.${SERVER_NAME})" {
        url.redirect = ( "^/(.*)" => "http://www.${SERVER_NAME}/$1" )
    }
    
    $HTTP["host"] =~ "^www.${SERVER_NAME}" {
    
        server.name = "${SERVER_NAME}"
        server.document-root = "${WWW_ROOT}"
    
        # Compress output
        compress.filetype = ("application/x-javascript", "application/javascript", "text/javascript", "text/x-js", "text/css", "text/html", "text/plain")
    
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
    
        url.rewrite-if-not-file = (
            #
            # Wordpress Standard Rewrites
            #
    
            # Exclude some directories from rewriting
            "^/(wp-admin|wp-includes|wp-content)/(.*)" => "\$0",
    
            # Pass all to handler
            "^/(.*)$" => "/index.php/\$1"
        )
    
        server.error-handler-404 = "/index.php"
    
    }
EOF

# Configure APC
cp -n /etc/php.d/apc.ini /etc/php.d/apc.ini.orig # backup
sed -i -e "s@^apc.shm_size.*@apc.shm_size=${APC_SHM_SIZE}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.ttl=.*@apc.ttl=${APC_TTL}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.user_ttl=.*@apc.user_ttl=${APC_USER_TTL}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.gc_ttl=.*@apc.gc_ttl=${APC_GC_TTL}@g" /etc/php.d/apc.ini

# Start / Restart
service lighttpd restart

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
