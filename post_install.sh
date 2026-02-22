#!/bin/sh

export LC_ALL=C

##############################################################################
# Enable services
##############################################################################

# Enable the service
sysrc nginx_enable=YES
sysrc php_fpm_enable=YES
sysrc mysql_enable=YES

##############################################################################
# Start MariaDB first
##############################################################################

# Start the service
service mysql-server start

##############################################################################
# Secure MariaDB (10.11 compatible)
##############################################################################

# Remove anonymous users and test database
mysql -u root <<EOF
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

##############################################################################
# Create user and database for Piwigo with unique password
##############################################################################

USER="piwigouser"
DB="piwigodb"

# Save the config values
echo "$DB" > /root/dbname
echo "$USER" > /root/dbuser

# Generate secure random password
PASS=$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 20 | head -n 1)
echo "$PASS" > /root/dbpassword

echo "Database User: $USER"
echo "Database Password: $PASS"

# Create database and user (MariaDB 10.11 compatible)
mysql -u root <<EOF
CREATE DATABASE ${DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${USER}'@'localhost' IDENTIFIED BY '${PASS}';
GRANT ALL PRIVILEGES ON ${DB}.* TO '${USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

##############################################################################
# Configure PHP
##############################################################################

# Copy a base PHP configuration
cp /usr/local/etc/php.ini-production /usr/local/etc/php.ini

# Modify settings in php.ini for Piwigo best performance
# recommended value of 512MB for php memory limit (avoid warning)
sed -i '' 's/^memory_limit = .*/memory_limit = 512M/' /usr/local/etc/php.ini
sed -i '' 's/^upload_max_filesize = .*/upload_max_filesize = 512M/' /usr/local/etc/php.ini
sed -i '' 's/^post_max_size = .*/post_max_size = 512M/' /usr/local/etc/php.ini
sed -i '' 's/^max_execution_time = .*/max_execution_time = 300/' /usr/local/etc/php.ini
sed -i '' 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /usr/local/etc/php.ini

##############################################################################
# Configure PHP-FPM
##############################################################################

# Editing WWW config file - www.conf
sed -i '' 's/^user = .*/user = www/' /usr/local/etc/php-fpm.d/www.conf
sed -i '' 's/^group = .*/group = www/' /usr/local/etc/php-fpm.d/www.conf
sed -i '' 's/^listen = .*/listen = 127.0.0.1:9000/' /usr/local/etc/php-fpm.d/www.conf

# Editing PHP-FPM config file - php-fpm.conf
sed -i '' 's/^;daemonize = yes/daemonize = yes/' /usr/local/etc/php-fpm.conf

##############################################################################
# Configure Nginx
##############################################################################

# Create a configuration directory to make managing individual server blocks easier
mkdir -p /usr/local/etc/nginx/conf.d

cat > /usr/local/etc/nginx/nginx.conf <<EOF
user  www;
worker_processes  auto;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;

    include /usr/local/etc/nginx/conf.d/*.conf;
}
EOF

cat > /usr/local/etc/nginx/conf.d/piwigo.conf <<EOF
server {
    listen 80;
    server_name _;

    root /usr/local/www/nginx/piwigo;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

##############################################################################
# Download and install latest Piwigo
##############################################################################

mkdir -p /usr/local/www/nginx
cd /usr/local/www/nginx

fetch https://piwigo.org/download/dlcounter.php?code=latest -o piwigo.zip
unzip piwigo.zip
rm piwigo.zip

chown -R www:www /usr/local/www/nginx

##############################################################################
# Start services
##############################################################################

service php-fpm start
service nginx start

##############################################################################
# Add plugin details to info file available in TrueNAS Plugin Additional Info
##############################################################################

echo "Host: 127.0.0.1" > /root/PLUGIN_INFO
echo "Database User: $USER" >> /root/PLUGIN_INFO
echo "Database Password: $PASS" >> /root/PLUGIN_INFO
echo "Database Name: $DB" >> /root/PLUGIN_INFO

echo "------------------------------------------------------------"
echo " Piwigo installation complete"
echo "------------------------------------------------------------"
echo "Host: 127.0.0.1"
echo "Database Name: $DB"
echo "Database User: $USER"
echo "Database Password: $PASS"
echo "------------------------------------------------------------"
