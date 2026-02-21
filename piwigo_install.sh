#!/bin/sh

# =================================================
# Piwigo Jail Installer v1.2
# TrueNAS CORE 13.5-RELEASE
# Caddy + PHP 8.3 + MariaDB 10.11
# =================================================
#
# =================================================
# run this before start chmod +x piwigo_install.sh
# =================================================
#
# Exit with an error if you use an undefined variable.
# If you're debugging use:
set -u   # safer, but no auto-exit
# If production and stable use this:
#set -euo pipefail 

# -------------------------------------------------
# Load configuration and helpers - FOR EDIT
# -------------------------------------------------

JAIL_NAME="piwigo135"			# your jail name
RELEASE="13.5-RELEASE"			# release you want to install
INTERFACE="vnet0"			# network interface of jail, check you other jails for clues :)
TIMEZONE="Europe/London"		# set your timezone
APP_NAME="Piwigo"			# name for Piwigo-Info.txt file with all credentials
DB_TYPE="MariaDB"			# type of maria database
DB_NAME="piwigo"			# name of database used by Piwigo
DB_USER="piwigo"			# name of user for database used by Piwigo
DB_ROOT_PASS=$(openssl rand -base64 15)	# autogenerate password for database root
DB_PASS=$(openssl rand -base64 15)	# autogenerate password for database user
PHP_VERSION="83"			# version of PHP you want to install
MARIADB_VERSION="1011"			# version of mariadb you want to install
REINSTALL="false"			# is it reinstal of Piwigo or fresh new Piwigo install

# -------------------------------------------------

# Check for Root Privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi


# Creating Jail
echo "Creating jail ${JAIL_NAME}..."

if iocage list | awk '{print $2}' | grep -q "^${JAIL_NAME}$"; then
    echo "Jail already exists."
else
    
iocage create -n ${JAIL_NAME} \
  -r ${RELEASE} \
  boot=on \
  dhcp=on \
  bpf="yes" \
  vnet=on
iocage start ${JAIL_NAME}
fi

#Start jail if its stopped
if ! iocage list | grep -q "^${JAIL_NAME}.*up"; then
    iocage start ${JAIL_NAME}
fi

# Package installation

echo "Bootstrapping pkg..."

iocage exec ${JAIL_NAME} env ASSUME_ALWAYS_YES=yes pkg bootstrap -f

echo "Updating packages..."

iocage exec ${JAIL_NAME} pkg update -f

echo "Installing required packages..."

iocage exec ${JAIL_NAME} pkg install -y \
  ImageMagick7-nox11 \
  mariadb${MARIADB_VERSION}-client \
  mariadb${MARIADB_VERSION}-server \
  php${PHP_VERSION} \
  php${PHP_VERSION}-ctype \
  php${PHP_VERSION}-dom \
  php${PHP_VERSION}-exif \
  php${PHP_VERSION}-filter \
  php${PHP_VERSION}-gd \
  php${PHP_VERSION}-iconv \
  php${PHP_VERSION}-mbstring \
  php${PHP_VERSION}-mysqli \
  php${PHP_VERSION}-pdo \
  php${PHP_VERSION}-pdo_mysql \
  php${PHP_VERSION}-session \
  php${PHP_VERSION}-simplexml \
  php${PHP_VERSION}-sodium \
  php${PHP_VERSION}-tokenizer \
  php${PHP_VERSION}-xml \
  php${PHP_VERSION}-zlib \
  php${PHP_VERSION}-zip \
  wget \
  p5-Image-ExifTool \
  mediainfo \
  caddy \
  unzip \
  bzip2 \
  ffmpeg \
  curl

# Enable services
iocage exec ${JAIL_NAME} sysrc mysql_enable=YES
iocage exec ${JAIL_NAME} sysrc php_fpm_enable=YES
iocage exec ${JAIL_NAME} sysrc caddy_enable=YES

# Stop service if somehow running
iocage exec ${JAIL_NAME} service mysql-server stop 2>/dev/null || true

# Remove old datadir if exists (important for reinstall)
#iocage exec ${JAIL_NAME} rm -rf /var/db/mysql

# Recreate clean datadir
#iocage exec ${JAIL_NAME} mkdir -p /var/db/mysql
#iocage exec ${JAIL_NAME} chown -R mysql:mysql /var/db/mysql
#iocage exec ${JAIL_NAME} chmod 750 /var/db/mysql
iocage exec ${JAIL_NAME} chown root:wheel /tmp
iocage exec ${JAIL_NAME} chmod 1777 /tmp
iocage exec ${JAIL_NAME} mkdir -p /var/run/mysql
iocage exec ${JAIL_NAME} chown mysql:mysql /var/run/mysql
iocage exec ${JAIL_NAME} mkdir -p /usr/local/www/piwigo/galleries
iocage exec ${JAIL_NAME} mkdir -p /usr/local/www/piwigo/upload
iocage exec ${JAIL_NAME} mkdir -p /usr/local/www/piwigo/local/config


# Enable and start
iocage exec ${JAIL_NAME} sysrc mysql_enable=YES
iocage exec ${JAIL_NAME} service mysql-server start

# Detect whether root has password or not
if iocage exec ${JAIL_NAME} mysql -u root -e "SHOW DATABASES;" >/dev/null 2>&1; then
    MYSQL_AUTH="-u root"
else
    MYSQL_AUTH="-u root -p${DB_ROOT_PASS}"
fi

# Check if DB exists
if iocage exec ${JAIL_NAME} mysql ${MYSQL_AUTH} -e "SHOW DATABASES LIKE '${DB_NAME}';" 2>/dev/null | grep -q ${DB_NAME}; then
    echo "Existing ${APP_NAME} database detected."
    echo "Starting reinstall..."
    REINSTALL="true"
fi

# Wait until socket is ready
until iocage exec ${JAIL_NAME} mysqladmin -u root -p"${DB_ROOT_PASS}" ping --silent 2>/dev/null; do
    sleep 1
done

# Create and Configure Database
if [ "${REINSTALL}" == "true" ]; then
	echo "You did a reinstall, but the ${DB_TYPE} root password AND ${APP_NAME} database password will be changed."
 	echo "New passwords will be saved in the root directory."
	iocage exec ${JAIL_NAME} mysql -u root -p"${DB_ROOT_PASS}" -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
	
cat <<EOF | iocage exec ${JAIL_NAME} tee /root/.my.cnf > /dev/null
# MySQL client config file
[client]
password=mypassword
EOF
	#iocage exec ${JAIL_NAME} sed -i '' "s|mypassword|${DB_ROOT_PASS}|" /root/.my.cnf

else
	
# Initialize database

echo "Initializing MariaDB..."

#iocage exec ${JAIL_NAME} /usr/local/bin/mariadb-install-db --defaults-file=~/.my.cnf
#iocage exec ${JAIL_NAME} mariadb-install-db \
#    --user=mysql \
#    --basedir=/usr/local \
#    --datadir=/var/db/mysql

echo "Securing MariaDB..."

# Set root password and create database/user
iocage exec ${JAIL_NAME} mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
fi

# Store root credentials safely
iocage exec ${JAIL_NAME} sh -c "echo '[client]' > /root/.my.cnf"
iocage exec ${JAIL_NAME} sh -c "echo 'user=root' >> /root/.my.cnf"
iocage exec ${JAIL_NAME} sh -c "echo 'password=${DB_ROOT_PASS}' >> /root/.my.cnf"
iocage exec ${JAIL_NAME} chmod 600 /root/.my.cnf

echo "Configuring PHP..."

iocage exec ${JAIL_NAME} cp /usr/local/etc/php.ini-production /usr/local/etc/php.ini

iocage exec ${JAIL_NAME} sed -i '' 's/max_execution_time = .*/max_execution_time = 300/' /usr/local/etc/php.ini
iocage exec ${JAIL_NAME} sed -i '' 's/post_max_size = .*/post_max_size = 100M/' /usr/local/etc/php.ini
iocage exec ${JAIL_NAME} sed -i '' 's/upload_max_filesize = .*/upload_max_filesize = 100M/' /usr/local/etc/php.ini
iocage exec ${JAIL_NAME} sed -i '' 's/memory_limit = .*/memory_limit = 512M/' /usr/local/etc/php.ini
iocage exec ${JAIL_NAME} sed -i '' "s|;date.timezone =.*|date.timezone = ${TIMEZONE}|" /usr/local/etc/php.ini

echo "Installing Piwigo..."

#iocage exec ${JAIL_NAME} mkdir -p /usr/local/www
iocage exec ${JAIL_NAME} fetch -o /tmp/piwigo.zip https://piwigo.org/download/dlcounter.php?code=latest
iocage exec ${JAIL_NAME} unzip /tmp/piwigo.zip -d /usr/local/www
iocage exec ${JAIL_NAME} chown -R www:www /usr/local/www

echo "Configuring Caddy..."

#iocage exec ${JAIL_NAME} fetch -o /usr/local/www/Caddyfile https://raw.githubusercontent.com/tschettervictor/bsd-apps/main/piwigo/includes/Caddyfile-nossl
cat <<EOF | iocage exec ${JAIL_NAME} tee /usr/local/www/Caddyfile > /dev/null
:80 {
    root * /usr/local/www/piwigo
    php_fastcgi 127.0.0.1:9000
    file_server
}
EOF

#iocage exec ${JAIL_NAME} sysrc php_fpm_enable=YES
#iocage exec ${JAIL_NAME} sysrc caddy_enable=YES
iocage exec ${JAIL_NAME} sysrc caddy_config=/usr/local/www/Caddyfile
iocage exec ${JAIL_NAME} service php_fpm start
iocage exec ${JAIL_NAME} service caddy start
iocage exec ${JAIL_NAME} service mysql-server restart

IP=$(iocage exec ${JAIL_NAME} ifconfig | awk '/inet / && $2 != "127.0.0.1" {print $2}')

echo ""
echo "======================================"
echo "Piwigo installed successfully!"
echo "Jail: ${JAIL_NAME}"
echo "IP Address: ${IP}"
echo
echo "Localhost: 127.0.0.1"
echo "DB User: ${DB_USER}"
echo "DB Pass: ${DB_PASS}"
echo "DB Name: ${DB_NAME}"
echo "DB Root Pass: ${DB_ROOT_PASS}"
echo "======================================"

if [ "${REINSTALL}" == "true" ]; then
	echo "======================================"
	echo "You did a reinstall."
	echo "Please use your old credentials to log in."
	echo "======================================"
fi
# Store Piwigo credentials
iocage exec ${JAIL_NAME} sh -c "echo '[Piwigo credentials]' > /${APP_NAME}-Info.txt"
iocage exec ${JAIL_NAME} sh -c "echo '${IP}' >> /${APP_NAME}-Info.txt"
iocage exec ${JAIL_NAME} sh -c "echo 'Localhost=127.0.0.1' >> /${APP_NAME}-Info.txt"
iocage exec ${JAIL_NAME} sh -c "echo 'DB User=${DB_USER}' >> /${APP_NAME}-Info.txt"
iocage exec ${JAIL_NAME} sh -c "echo 'DB password=${DB_PASS}' >> /${APP_NAME}-Info.txt"
iocage exec ${JAIL_NAME} sh -c "echo 'DB Name=${DB_NAME}' >> /${APP_NAME}-Info.txt"
iocage exec ${JAIL_NAME} sh -c "echo 'DB Root password=${DB_ROOT_PASS}' >> /${APP_NAME}-Info.txt"
iocage exec ${JAIL_NAME} chmod 600 /${APP_NAME}-Info.txt
echo "======================================"
echo "All passwords are saved in /${APP_NAME}-Info.txt"
echo "======================================"
