#!/bin/bash

LOGFILE="/var/log/deployment.log"
STATE_FILE="/var/log/deployment_state.txt"
LOCKFILE="/var/lock/deployment.lock"
ALL_STEPS_EXECUTED=true

function load_env() {
    if [ -f .env ]; then
      set -a
      source .env
      set +a
    else
        echo ".env file not found. Please create it with the following variables:"
        echo "MYSQL_ROOT_PASSWORD, WORDPRESS_DB, WORDPRESS_USER, WORDPRESS_PASSWORD, JOOMLA_DB, JOOMLA_USER, JOOMLA_PASSWORD, TELEGRAM_TOKEN, TELEGRAM_CHAT_ID"
        exit 1
    fi
}

function check_lockfile() {
    exec 200>$LOCKFILE
    if ! flock -n 200; then
        echo "This script is already running" | tee -a $LOGFILE
        exit 1
    fi
}


function send_telegram_message() {
    local message=$1
    curl -s -X POST https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage -d chat_id=$TELEGRAM_CHAT_ID -d text="$message" > /dev/null
}

function check_root() {
    echo "Checking if running via sudo..." | tee -a $LOGFILE 2>/dev/null
    if [ "$EUID" -ne 0 ]; then
        local message="Error: Script must be run as root."
        echo "$message" | tee -a $LOGFILE
        exit 1
    fi
}

function install_packages() {
    if grep -q "install_packages" $STATE_FILE; then
        echo "Packages already installed, skipping..." | tee -a $LOGFILE
        return
    fi

    echo "Installing necessary packages..." | tee -a $LOGFILE
    apt-get update | tee -a $LOGFILE
    apt-get install -y apache2 nginx mysql-server php php-mysql libapache2-mod-php php-xml php-curl php-gd php-mbstring php-zip wget unzip | tee -a $LOGFILE

    echo "install_packages" >> $STATE_FILE
}

function secure_mysql() {
    if grep -q "secure_mysql" $STATE_FILE; then
        echo "MySQL already secured, skipping..." | tee -a $LOGFILE
        return
    fi

    echo "Securing MySQL installation..." | tee -a $LOGFILE
    mysql_secure_installation <<EOF | tee -a $LOGFILE
n
y
y
y
y
EOF

    echo "secure_mysql" >> $STATE_FILE
}

function setup_mysql_databases() {
    if grep -q "setup_mysql_databases" $STATE_FILE; then
        echo "MySQL databases already set up, skipping..." | tee -a $LOGFILE
        return
    fi

    echo "Setting up MySQL databases..." | tee -a $LOGFILE
    mysql -u root -p$MYSQL_ROOT_PASSWORD <<MYSQL_SCRIPT | tee -a $LOGFILE
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
CREATE DATABASE $WORDPRESS_DB;
CREATE USER '$WORDPRESS_USER'@'localhost' IDENTIFIED BY '$WORDPRESS_PASSWORD';
GRANT ALL PRIVILEGES ON $WORDPRESS_DB.* TO '$WORDPRESS_USER'@'localhost';

CREATE DATABASE $JOOMLA_DB;
CREATE USER '$JOOMLA_USER'@'localhost' IDENTIFIED BY '$JOOMLA_PASSWORD';
GRANT ALL PRIVILEGES ON $JOOMLA_DB.* TO '$JOOMLA_USER'@'localhost';

FLUSH PRIVILEGES;
MYSQL_SCRIPT

    echo "setup_mysql_databases" >> $STATE_FILE
}

function configure_web_servers() {
    if grep -q "configure_web_servers" $STATE_FILE; then
        echo "Web servers already configured, skipping..." | tee -a $LOGFILE
        return
    fi
    echo "Configuring Apache and Nginx..." | tee -a $LOGFILE
    cp configs/default /etc/nginx/sites-available/ | tee -a $LOGFILE
    sed -i 's/^Listen 80$/Listen 8080\nListen 8081/' /etc/apache2/ports.conf | tee -a $LOGFILE

    echo "configure_web_servers" >> $STATE_FILE
}

function deploy_wordpress() {
    if grep -q "deploy_wordpress" $STATE_FILE; then
        echo "WordPress already deployed, skipping..." | tee -a $LOGFILE
        ALL_STEPS_EXECUTED=false
        return
    fi

    local WORDPRESS_CONFIG="/var/www/html/wordpress/wp-config.php"
    local APACHE_CONF_DIR="/etc/apache2/sites-available"

    echo "Deploying WordPress..." | tee -a $LOGFILE
    wget https://wordpress.org/latest.zip | tee -a $LOGFILE
    unzip -o latest.zip -d /var/www/html/ | tee -a $LOGFILE
    rm latest.zip | tee -a $LOGFILE

    cp /var/www/html/wordpress/wp-config-sample.php $WORDPRESS_CONFIG | tee -a $LOGFILE
    sed -i "s/database_name_here/$WORDPRESS_DB/" $WORDPRESS_CONFIG | tee -a $LOGFILE
    sed -i "s/username_here/$WORDPRESS_USER/" $WORDPRESS_CONFIG | tee -a $LOGFILE
    sed -i "s/password_here/$WORDPRESS_PASSWORD/" $WORDPRESS_CONFIG | tee -a $LOGFILE

    echo "define('WP_HOME', 'http://wordpress.example.com');" >> $WORDPRESS_CONFIG | tee -a $LOGFILE
    echo "define('WP_SITEURL', 'http://wordpress.example.com');" >> $WORDPRESS_CONFIG | tee -a $LOGFILE
    cp configs/wordpress.conf $APACHE_CONF_DIR/wordpress.conf | tee -a $LOGFILE

    chown -R www-data:www-data /var/www/html/wordpress | tee -a $LOGFILE

    echo "deploy_wordpress" >> $STATE_FILE
}

function deploy_joomla() {
    if grep -q "deploy_joomla" $STATE_FILE; then
        echo "Joomla already deployed, skipping..." | tee -a $LOGFILE
        ALL_STEPS_EXECUTED=false
        return
    fi

    local JOOMLA_CONFIG="/var/www/html/joomla/installation/configuration.php"
    local APACHE_CONF_DIR="/etc/apache2/sites-available"

    echo "Deploying Joomla..." | tee -a $LOGFILE
    wget https://downloads.joomla.org/cms/joomla3/3-10-12/Joomla_3-10-12-Stable-Full_Package.zip | tee -a $LOGFILE
    unzip -o Joomla_3-10-12-Stable-Full_Package.zip -d /var/www/html/joomla | tee -a $LOGFILE
    rm Joomla_3-10-12-Stable-Full_Package.zip | tee -a $LOGFILE
    cp /var/www/html/joomla/installation/configuration.php-dist $JOOMLA_CONFIG | tee -a $LOGFILE

    sed -i "s/public \$user = ''/public \$user = '$JOOMLA_USER'/" $JOOMLA_CONFIG | tee -a $LOGFILE
    sed -i "s/public \$password = ''/public \$password = '$JOOMLA_PASSWORD'/" $JOOMLA_CONFIG | tee -a $LOGFILE
    sed -i "s/public \$db = ''/public \$db = '$JOOMLA_DB'/" $JOOMLA_CONFIG | tee -a $LOGFILE
    cp configs/joomla.conf $APACHE_CONF_DIR/joomla.conf | tee -a $LOGFILE

    chown -R www-data:www-data /var/www/html/joomla | tee -a $LOGFILE

    echo "deploy_joomla" >> $STATE_FILE
}

function start_services() {
    if grep -q "start_services" $STATE_FILE; then
        echo "Services already started, skipping..." | tee -a $LOGFILE
        return
    fi

    echo "Starting and configuring services..." | tee -a $LOGFILE
    systemctl start apache2 | tee -a $LOGFILE
    a2ensite wordpress.conf | tee -a $LOGFILE
    a2ensite joomla.conf | tee -a $LOGFILE
    systemctl reload apache2 | tee -a $LOGFILE
    systemctl restart nginx | tee -a $LOGFILE

    echo "start_services" >> $STATE_FILE
}

function send_notification() {
    if [ "$ALL_STEPS_EXECUTED" = true ] && [ "$(wc -l < "$STATE_FILE")" -eq 7 ]; then
      local message="Deployment completed successfully!"
      curl -s -X POST https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage -d chat_id=$TELEGRAM_CHAT_ID -d text="$message" > /dev/null
    else
      echo "Notification not sent: some steps were skipped" | tee -a $LOGFILE
    fi
}

function main() {
    set -o errexit
    set -o nounset
    set -o pipefail
    check_root 
    load_env
    check_lockfile
    install_packages  
    secure_mysql
    setup_mysql_databases 
    configure_web_servers 
    deploy_wordpress 
    deploy_joomla 
    start_services  
    send_notification
}

main
