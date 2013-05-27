#!/bin/bash
#
# Setup Nginx w/ APC for Magento, with PHP-FPM
#
# Assumes the host is clean unconfigured CentOS 6 / EL 6 derivatives (inc Amazon Linux AMI). Should be idempotent.
#
# Mostly based on http://www.magentocommerce.com/wiki/1_-_installation_and_configuration/configuring_nginx_for_magento
#
# Adlibre Pty Ltd 2013
#

## Configuration
SERVER_NAME=`hostname -d`
WWW_ROOT="/srv/www/${SERVER_NAME}"
APC_SHM_SIZE='256M'
SSL=False
# APC: use 0, 600, 600 to flush cache in case of APC memory exhaustion (prevents fragmentation too) 
APC_TTL=0 
APC_USER_TTL=600
APC_GC_TTL=600
PHP_FCGI_CHILDREN='$(expr 4 \* `nproc`)' # Autoscale based on number of cpu's on startup or hardcode to fix.
PHP_FCGI_MAX_REQUESTS=1000

## Constants
LOGFILE='install.log'

echo "### Beginning Install ###"

( # Start log capture

## Start
# Install EPEL Package Source if not Amazon AMI
if grep -qv Amazon /etc/system-release 2> /dev/null; then
    rpm -Uvh http://download.fedoraproject.org/pub/epel/6/$(uname -m)/epel-release-6-8.noarch.rpm
fi

# Install base packages
yum -y install nginx php-fpm php php-mysql php-gd php-xml php-pecl-apc php-soap

mkdir -p ${WWW_ROOT}

# turn on services
chkconfig php-fpm on
chkconfig nginx on

# Configure Spawn-FCGI
cp -n /etc/php-fpm.d/www.conf /etc/php-fpm.d/www.conf.orig # backup
cp -n /etc/php-fpm.conf /etc/php-fpm.conf.orig # backup

sed -i -e 's@^user =.*$@user = nginx@g' /etc/php-fpm.d/www.conf
sed -i -e 's@^group =.*$@group = nginx@g' /etc/php-fpm.d/www.conf
sed -i -e 's@^pm.max_children =.*$@pm.max_children = 12@g' /etc/php-fpm.d/www.conf
sed -i -e 's@^pm.max_spare_servers =.*$@pm.max_spare_servers = 5@g' /etc/php-fpm.d/www.conf
sed -i -e "s@^;pm.max_requests =.*\$@pm.max_requests = ${PHP_FCGI_MAX_REQUESTS}@g" /etc/php-fpm.d/www.conf
sed -i -e 's@^php_value\[session.save_path\] =.*$@php_value\[session.save_path\] = /var/lib/nginx/session@g' /etc/php-fpm.d/www.conf

sed -i -e 's@^;emergency_restart_threshold =.*$@emergency_restart_threshold = 1@g' /etc/php-fpm.conf 
sed -i -e 's@^;emergency_restart_interval =.*$@emergency_restart_interval = 1m@g' /etc/php-fpm.conf 

# Configure Nginx vhost
cat > /etc/nginx/conf.d/${SERVER_NAME}-magento.conf << EOF
    # Magento Nginx Config for ${SERVER_NAME}
    
    server {
        listen  80;
        server_name_in_redirect off;
        server_name ${SERVER_NAME} www.${SERVER_NAME};
        root    ${WWW_ROOT};
        index   index.html index.htm index.php; # Allow a static html file to be shown first        
$(
if [ $SSL == True ]; then
cat << EOFA
        
        # SSL
        listen 443 default ssl;

        # SSL BEAST mitigation
        ssl_ciphers RC4:HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
        
        ssl_certificate /etc/pki/tls/certs/${SERVER_NAME}.crt;
        ssl_certificate_key /etc/pki/tls/private/${SERVER_NAME}.key;
        
EOFA
fi
)
        if (\$server_port = 443) { set \$https on; }
        if (\$server_port = 80) { set \$https off; }
        
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
        gzip_types text/css text/x-component application/x-javascript application/javascript text/javascript text/x-js text/richtext image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;
        gzip_buffers 16 8k;
        
        # Max file upload
        client_max_body_size 32M;
        
        location / {
            index index.html index.php; ## Allow a static html file to be shown first
            try_files \$uri \$uri/ @handler; ## If missing pass the URI to Magento's front handler
            expires 30d; ## Assume all files are cachable
        }
        
        # Static content 
        location ~* ^.+\.(css|ico|js|png|gif|jpg|jpeg)$ {
            access_log off;
            expires max;
        }
        
        ## These locations would be hidden by .htaccess normally
        location ^~ /app/                { deny all; }
        location ^~ /includes/           { deny all; }
        location ^~ /lib/                { deny all; }
        location ^~ /media/downloadable/ { deny all; }
        location ^~ /pkginfo/            { deny all; }
        location ^~ /report/config.xml   { deny all; }
        location ^~ /var/                { deny all; }
        
        location /var/export/ { ## Allow admins only to view export folder
            auth_basic           "Restricted"; ## Message shown in login window
            auth_basic_user_file htpasswd; ## See /etc/nginx/htpasswd
            autoindex            on;
        }
        
        location  /. { ## Disable .htaccess and other hidden files
            return 404;
        }
     
        location @handler { ## Magento uses a common front handler
            rewrite / /index.php;
        }
     
        location ~ .php/ { ## Forward paths like /js/index.php/x.js to relevant handler
            rewrite ^(.*.php)/ $1 last;
        }   
        
        # Pass PHP scripts on to PHP-FASTCGI
        location ~ \.php$ {
            if (!-e \$request_filename) { rewrite / /index.php last; } ## Catch 404s that try_files miss
            include /etc/nginx/fastcgi_params;
            fastcgi_pass  127.0.0.1:9000;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_read_timeout 300; # increase timeout since our mysql is on different servers
            fastcgi_param HTTPS \$https;
            fastcgi_param  MAGE_RUN_CODE default; ## Store code is defined in administration > Configuration > Manage Stores
            fastcgi_param  MAGE_RUN_TYPE store;
        }
        
    }
EOF

# Configure PHP
cp -n /etc/php.ini /etc/php.ini.orig # backup
sed -i -e "s@^short_open_tag.*@short_open_tag = On@g" /etc/php.ini # Some plugins need this
sed -i -e "s@^zlib.output_compression.*@zlib.output_compression = Off@g" /etc/php.ini # Turn this off if W3 Total Cache / Nginx is handing compression
sed -i -e "s@^post_max_size.*@post_max_size = 32M@g" /etc/php.ini # Allow for 32M Upload
sed -i -e "s@^upload_max_filesize.*@upload_max_filesize = 32M@g" /etc/php.ini # Allow for 32M Upload
sed -i -e "s@^session.save_path.*@session.save_path = "/var/lib/nginx/session"@g" /etc/php.ini # Move session to dir owned by Nginx

# Configure PHP Session directory
mkdir -p /var/lib/nginx/session
chmod 770 /var/lib/nginx/session
chown root:nginx /var/lib/nginx/session

# Configure APC
cp -n /etc/php.d/apc.ini /etc/php.d/apc.ini.orig # backup
sed -i -e "s@^apc.shm_size=.*@apc.shm_size=${APC_SHM_SIZE}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.ttl=.*@apc.ttl=${APC_TTL}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.user_ttl=.*@apc.user_ttl=${APC_USER_TTL}@g" /etc/php.d/apc.ini
sed -i -e "s@^apc.gc_ttl=.*@apc.gc_ttl=${APC_GC_TTL}@g" /etc/php.d/apc.ini

# Start / Restart
service php-fpm restart
service nginx restart

) 2>&1 1>> ${LOGFILE} | tee -a ${LOGFILE} # stderr to console, stdout&stderr to logfile

echo "### Install Complete ###"
