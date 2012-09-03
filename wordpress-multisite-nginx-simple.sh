#!/bin/bash
#
# Setup Nginx w/ APC for Wordpress Multisite + W3 Total Cache (Simple)
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
# Install EPEL Package Source
rpm -Uvh http://download.fedoraproject.org/pub/epel/6/$(uname -m)/epel-release-6-7.noarch.rpm

# Install base packages
yum -y install nginx spawn-fcgi php php-mysql php-gd php-xml php-pecl-apc

mkdir -p ${WWW_ROOT}

# turn on services
chkconfig spawn-fcgi on
chkconfig nginx on

# Configure Spawn-FCGI
cp -n /etc/sysconfig/spawn-fcgi /etc/sysconfig/spawn-fcgi.orig # backup
cat > /etc/sysconfig/spawn-fcgi << EOF
OPTIONS="-u nginx -g nginx -p 9000 -C ${PHP_FCGI_CHILDREN} -F 1  -P /var/run/spawn-fcgi.pid -- PHP_FCGI_MAX_REQUESTS=${PHP_FCGI_MAX_REQUESTS} /usr/bin/php-cgi"
EOF

# Configure Nginx vhost
cat > /etc/nginx/conf.d/${SERVER_NAME}-wordpress.conf << EOF
    # Wordpress Nginx Config for ${SERVER_NAME}
    
    server {
        listen  80  default;
        server_name_in_redirect off;
        server_name ${SERVER_NAME};
        root    ${WWW_ROOT};
        index   index.php index.html index.htm;
        
        # Redirect to naked domain
        if (\$host ~* www\.(.*)) {
            set \$host_without_www \$1;
            rewrite ^/(.*)$ \$scheme://\$host_without_www/\$1 permanent;
        }
        
        # Output compression
        gzip on;
        gzip_disable "msie6";
        gzip_http_version 1.0;
        gzip_vary on;
        gzip_comp_level 5;
        gzip_proxied any;
        gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
        gzip_buffers 16 8k;    	
        
        # WPMS theme, plugin and other static content 
        location ~* ^.+\.(css|ico|js|png|gif|jpg|jpeg)$ {
            # WPMS File Handling
            rewrite ^.*/files/(.*) /wp-includes/ms-files.php?file=\$1 last;
            access_log off;
            expires max;
        }
        
        # WPMS root dir
        location / {
            
            # WPMS File Handling
            rewrite ^.*/files/(.*) /wp-includes/ms-files.php?file=\$1 last;
            
            # if the requested file exists, return it immediately
            if (-f \$request_filename) {
                break;
            }
            
            ## W3 Total CACHE BEGIN
            set \$totalcache_file '';
            set \$totalcache_uri \$request_uri;
            
            if (\$request_method = POST) {
                set \$totalcache_uri '';
            }
            
            # Using pretty permalinks, so bypass the cache for any query string
            if (\$query_string) {
                set \$totalcache_uri '';
            }
            
            if (\$http_cookie ~* "comment_author_|wordpress|wp-postpass_" ) {
                set \$totalcache_uri '';
            }
            
            # if we haven't bypassed the cache, specify our totalcache file
            if (\$totalcache_uri ~ ^(.+)$) {
                set \$totalcache_file /wp-content/w3tc-\$http_host/pgcache/\$1/_default_.html;
            }
            
            # only rewrite to the totalcache file if it actually exists
            if (-f \$document_root\$totalcache_file) {
                rewrite ^(.*)$ \$totalcache_file break;
            }                 
            ## W3 Total CACHE END
            
            # all other requests go to WordPress
            if (!-e \$request_filename) {
                rewrite . /index.php last;
            }
        }
        
        # WPMS x-sendfile to avoid php readfile()
        location ^~ /blogs.dir {
            internal;
            alias ${WWW_ROOT}/wp-content/blogs.dir;
        }
        
        # Pass PHP scripts on to PHP-FASTCGI
        location ~ \.php$ {
            include /etc/nginx/fastcgi_params;
            fastcgi_pass  127.0.0.1:9000;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_read_timeout 300; # increase timeout since our mysql is on different servers
        }
        
        # Don't serve .htaccess, .svn or .git
        location ~ \.(htaccess|svn|git) {
            deny  all;
        }
        
    }
EOF

# Configure PHP
cp -n /etc/php.ini /etc/php.ini.orig # backup
sed -i -e "s@^short_open_tag.*@short_open_tag = On@g" /etc/php.ini # Some plugins need this
sed -i -e "s@^zlib.output_compression.*@zlib.output_compression = On@g" /etc/php.ini

# Configure APC
cp -n /etc/php.d/apc.ini /etc/php.d/apc.ini.orig # backup
sed -i -e "s@^apc.shm_size=.*@apc.shm_size=${APC_SHM_SIZE}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.ttl=.*@apc.ttl=${APC_TTL}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.user_ttl=.*@apc.user_ttl=${APC_USER_TTL}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.gc_ttl=.*@apc.gc_ttl=${APC_GC_TTL}@g" /etc/php.d/apc.ini

# Start / Restart
service spawn-fcgi restart
service nginx restart

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
