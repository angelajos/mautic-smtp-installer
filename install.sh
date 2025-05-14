#!/bin/bash

# --------------------------
# Mautic + SMTP Installer
# For Ubuntu 22.04
# --------------------------

set -e

# Define colors
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Prompt for domain
read -p "mail.tipspilot.com" DOMAIN
read -p "operations@media-labs.io" EMAIL

# Update & install required packages
echo -e "${GREEN}Updating system and installing packages...${NC}"
apt update && apt upgrade -y
apt install -y nginx mariadb-server php php-cli php-fpm php-mysql php-curl php-mbstring \
  php-xml php-zip php-intl php-imap php-bcmath unzip curl git certbot \
  python3-certbot-nginx postfix opendkim opendkim-tools composer

# Secure MariaDB
echo -e "${GREEN}Securing MariaDB...${NC}"
mysql_secure_installation <<EOF

Y
Y
Y
Y
EOF

# Create DB and user
DB_NAME="mauticdb"
DB_USER="mauticuser"
DB_PASS="$(openssl rand -base64 12)"

mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Install Mautic
echo -e "${GREEN}Installing Mautic...${NC}"
cd /var/www/
git clone https://github.com/mautic/mautic.git
cd mautic
composer install --no-dev
chown -R www-data:www-data /var/www/mautic
chmod -R 755 /var/www/mautic

# Configure Nginx
cat > /etc/nginx/sites-available/mautic <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/mautic;
    index index.php index.html;

    location / {
        try_files \$uri /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

ln -s /etc/nginx/sites-available/mautic /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# SSL with Certbot
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Configure Postfix
postconf -e "myhostname = $DOMAIN"
postconf -e "mydestination = localhost"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
systemctl restart postfix

# Finish
clear
echo -e "${GREEN}Installation completed successfully.${NC}"
echo "Mautic URL: https://$DOMAIN"
echo "MySQL DB: $DB_NAME"
echo "DB User: $DB_USER"
echo "DB Password: $DB_PASS"
echo "Configure SPF, DKIM, DMARC in your DNS for inboxing."
echo "Use mail-tester.com to verify email deliverability."
