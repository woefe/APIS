PATH_TO_WEBSERVER="/var/www/cloud"
SERVER_NAME=""
VERSION=""
STARTPATH=$PWD

function install_nginx_and_other_stuff(){
   echo $"Installing nginx and php..."
   apt-get -qq install nginx php5 php5-common php5-cgi php5-gd php-xml-parser php5-intl sqlite php5-sqlite curl libcurl3 php5-curl php-pear php-apc php5-fpm memcached php5-memcache smbclient openssl ssl-cert varnish dphys-swapfile
   echo $"Searching for packages that are no longer needed..."
   apt-get -qq autoremove

   clear
   print_message $"SSL-Certificate" $"The next step will create a ssl certificate.\nDon't leave the field 'Common Name' blank.\nHit Enter to continue."

   mkdir -p /etc/nginx/ssl && cd /etc/nginx/ssl
   while true; do
      rm -f *
      openssl req $@ -new -x509 -days 365 -nodes -out server.crt -keyout server.key &&
      chmod 600 server.crt &&
      chmod 600 server.key &&
      break

      echo $"An error occurred during the last Step. Repeating"
      for i in 1 2 3; do
         sleep 1 && echo -n "."
      done
      echo
      sleep 1
   done

   echo $"Creating /etc/nginx/nginx.conf..."
   create_nginx_conf_files

   echo $"Editing /etc/php5/fpm/php.ini..."
   edit_phpini

   echo $"Editing /etc/dphys-swapfile"
   cat > /etc/dphys-swapfile << EOF
CONF_SWAPSIZE=768

EOF
   dphys-swapfile setup
   dphys-swapfile swapon

   echo $"Checking for locale en_US.UTF-8..."
   grep -Eq "^# en_US.UTF-8 UTF-8$" /etc/locale.gen && sed -i -e "s/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" /etc/locale.gen && locale-gen
   return 0
}

function install_oc(){
   echo $"Decompressing owncloud-$VERSION.tar.bz2..."
   cd $STARTPATH
   tar -xj  -f owncloud-$VERSION.tar.bz2
   mkdir -p  $PATH_TO_WEBSERVER

   echo $"Copying decompressed files to '$PATH_TO_WEBSERVER'..."
   cp -R  owncloud/* $PATH_TO_WEBSERVER

   echo $"Setting permissions for '$PATH_TO_WEBSERVER'..."
   cd $PATH_TO_WEBSERVER
   chown -R  www-data:www-data ..
   chmod -R  644 .
   find . -type d -exec chmod  755  {} \;

   if $DATA_TO_EXTERNAL_DISK; then
      echo $"Creating conf.php..."
      create_minimal_php_conf
      mkdir  $EXTERNAL_DATA_DIR
      chown -R  www-data:www-data $EXTERNAL_DATA_DIR
   fi

   echo $"Cleaning up..."
   cd $STARTPATH
   rm -R  owncloud{,*.tar.bz2,.md5}
   service php5-fpm restart
   service nginx restart
}

function create_nginx_conf_files(){

cat > /etc/nginx/nginx.conf << EOF
user www-data;
worker_processes 1;
pid /var/run/nginx.pid;

events {
   worker_connections 100;
}

http {
   sendfile on;
   tcp_nopush on;
   tcp_nodelay on;
   keepalive_timeout 65;
   types_hash_max_size 2048;

   include /etc/nginx/mime.types;
   default_type application/octet-stream;

   access_log /var/log/nginx/access.log;
   error_log /var/log/nginx/error.log;

   gzip on;
   gzip_disable "msie6";

   include /etc/nginx/conf.d/*.conf;
   include /etc/nginx/sites-enabled/*;
}
EOF

# Based on http://doc.owncloud.org/server/5.0/admin_manual/installation/installation_others.html?highlight=nginx
cat > /etc/nginx/sites-available/owncloud << EOF
# redirect http to https.
server {
   listen 80;
   return https://\$host\$request_uri;  # enforce https
}

# owncloud (ssl/tls)
server {
   listen 443 ssl;
   server_name $SERVER_NAME;

   ssl_certificate /etc/nginx/ssl/server.crt;
   ssl_certificate_key /etc/nginx/ssl/server.key;

   # Path to the root of your installation
   root $PATH_TO_WEBSERVER;

   client_max_body_size 1G; # set max upload size
   fastcgi_buffers 64 4K;

   rewrite ^/caldav(.*)$ /remote.php/caldav\$1 redirect;
   rewrite ^/carddav(.*)$ /remote.php/carddav\$1 redirect;
   rewrite ^/webdav(.*)$ /remote.php/webdav\$1 redirect;

   index index.php;
   error_page 403 = /core/templates/403.php;
   error_page 404 = /core/templates/404.php;

   # deny direct access
   location ~ ^/(data|config|\.ht|db_structure\.xml|README) {
      deny all;
   }

   location / {
      # The following 2 rules are only needed with webfinger
      rewrite ^/.well-known/host-meta /public.php?service=host-meta last;
      rewrite ^/.well-known/host-meta.json /public.php?service=host-meta-json last;

      rewrite ^/.well-known/carddav /remote.php/carddav/ redirect;
      rewrite ^/.well-known/caldav /remote.php/caldav/ redirect;

      rewrite ^(/core/doc/[^\/]+/)$ \$1/index.html;

      try_files \$uri \$uri/ index.php;
   }

   location ~ ^(.+?\.php)(/.*)?$ {
      try_files \$1 = 404;

      include fastcgi_params;
      fastcgi_param PATH_INFO \$2;
      fastcgi_param HTTPS on;
      fastcgi_pass 127.0.0.1:7659;
   }

   # Optional: set long EXPIRES header on static assets
   location ~* ^.+\.(jpg|jpeg|gif|bmp|ico|png|css|js|swf)$ {
      expires 30d;
      # Optional: Don't log access to assets
      access_log off;
   }
}

EOF

rm /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/owncloud /etc/nginx/sites-enabled/owncloud
}

function edit_phpini(){
   sed -i -e "s/^upload_max_filesize.*/upload_max_filesize = 1000M/" /etc/php5/fpm/php.ini
   sed -i -e "s/^post_max_size.*/post_max_size = 1100M/" /etc/php5/fpm/php.ini
   sed -i -e "s/^memory_limit.*/memory_limit = 256M/" /etc/php5/fpm/php.ini
   sed -i -e "s:.upload_tmp_dir.*:upload_tmp_dir = /srv/http/owncloud/data:" /etc/php5/fpm/php.ini
   sed -i -e "s|listen =.*|listen = 127.0.0.1:7659|g" /etc/php5/fpm/pool.d/www.conf
   mkdir -p  /srv/http/owncloud/data
   chown  www-data:www-data /srv/http/owncloud/data
}

function create_minimal_php_conf(){
cat > $PATH_TO_WEBSERVER/config/config.php << EOF
<?php
\$CONFIG = array (
  'datadirectory' => '$EXTERNAL_DATA_DIR',
  'dbtype' => 'sqlite3',
  'installed' => false,
);
EOF
chown  www-data:www-data $PATH_TO_WEBSERVER/config/config.php
}


function download_and_check_oc(){
   OWNCLOUD_URL="http://download.owncloud.org/community/owncloud-$VERSION.tar.bz2"
   OWNCLOUD_CHECKSUM_URL="http://download.owncloud.org/community/owncloud-$VERSION.tar.bz2.md5"

   # Download ownCloud archive
   echo $"Downloading owncloud-$VERSION.tar.bz2..."
   wget -q $OWNCLOUD_URL || (echo $"Download failed" && return 1)
   wget -qO - $OWNCLOUD_CHECKSUM_URL | sed s/-/owncloud-$VERSION.tar.bz2/g > owncloud.md5
   echo -n $"Checking download..."
   md5sum -c owncloud.md5 || (error_msg $"Download failed" && return 1)
}


# check and install dependencies
function sys_update(){
   echo $"Updating the operating systems's software (might take a while)..."
   apt-get -qq update &&
   apt-get -qq upgrade &&
   if [ $? -ne 0 ]; then
      echo $"Update failed."
      echo $"Bye..."
      return 1
   fi
   clear
}

function get_latest_version(){
   wget -qO - http://apps.owncloud.com/updater.php?version=5x00x10x1375797810.1234x1375797810.3456xstablex | grep versionstring | grep -Eo "[0-9]{1,2}.[0-9]{1,2}.[0-9]{1,2}"
}

function install_owncloud(){

   VERSION=$(get_latest_version)
   SERVER_NAME=$(ifconfig | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -Ev "127.0.0.1|255|.255" | head -n1)
   print_message $"IP address and version" $"This IP will be used to set up your ownCloud: $SERVER_NAME\nThis will be the IP you have to enter in your webbrowser after the script has finished.\nThis version of ownCloud will be installed: $VERSION"
   
   sys_update
   EXTERNAL_DATA_DIR="/mnt/data/owncloudData"

   download_and_check_oc &&
   install_nginx_and_other_stuff &&
   clear &&
   install_oc
}

function get_installed_version(){
   grep getVersionString -1 $PATH_TO_WEBSERVER/lib/util.php | sed -n 3p | tr -d "return\ \'\;\t"
}

function update_owncloud(){
   clear
   if [ ! -f $PATH_TO_WEBSERVER/config/config.php ]; then
      error_msg $"ownCloud is not installed properly or wasn't installed by this script and thus can't be updated"
      return 1
   fi
   INSTALLED_VERION=$(get_installed_version)
   LATEST_VERSION=$(get_latest_version)
   if [ "$LATEST_VERSION" == "$INSTALLED_VERSION" ]; then
      error_msg $"Latest version is already installed."
      return 1
   fi
   sys_update
   download_and_check_oc

   echo $"Decompressing owncloud-$VERSION.tar.bz2..."
   tar -xjf owncloud-$VERSION.tar.bz2

   echo $"Copying decompressed files to '$PATH_TO_WEBSERVER'..."
   cp -R  owncloud/* $PATH_TO_WEBSERVER

   echo $"Setting permissions for '$PATH_TO_WEBSERVER'..."
   cd $PATH_TO_WEBSERVER
   chown -R  www-data:www-data ..
   chmod -R  644 .
   find . -type d -exec chmod  755 {} \;

   echo $"Cleaning up..."
   cd $STARTPATH
   rm -r  owncloud{,*.tar.bz2,.md5}
   return
}

function remove_owncloud(){
   clear
   if [ ! -f $PATH_TO_WEBSERVER/config/config.php ]; then
      error_msg $"ownCloud is not installed properly or wasn't installed by this script and thus can't be removed"
      return 1
   fi
   yes_no $"Are you sure you want to continue?" || return 1
   
   if yes_no $"Do you want to remove ownCloud's datadirectory?"; then
      choice="y"
   else
      choice="n"
   fi

   DATA_DIR=$(grep datadirectory $PATH_TO_WEBSERVER/config/config.php | cut -d\' -f4)

   if [ "$choice" == "y" ] && [[ $DATA_DIR != $PATH_TO_WEBSERVER/* ]]; then
      rm -r  $DATA_DIR
      rm -r  $PATH_TO_WEBSERVER
   elif [ "$choice" == "y" ] && [[ $DATA_DIR == $PATH_TO_WEBSERVER/* ]]; then
      rm -r  $PATH_TO_WEBSERVER
   elif [ "$choice" == "n" ] && [[ $DATA_DIR != $PATH_TO_WEBSERVER/* ]]; then
      rm -r  $PATH_TO_WEBSERVER
   elif [ "$choice" == "n" ] && [[ $DATA_DIR == $PATH_TO_WEBSERVER/* ]]; then
      find $PATH_TO_WEBSERVER/* -maxdepth 0 ! -name data -exec rm -r  {} \;
   fi

   [ -e /etc/dhcp/dhclient-exit-hooks.d/01_hostname ] && rm  /etc/dhcp/dhclient-exit-hooks.d/01_hostname
   [ -e /etc/dhcp/dhclient-exit-hooks.d/02_nginxconf ] && rm  /etc/dhcp/dhclient-exit-hooks.d/02_nginxconf
   rm -r  /srv/http/owncloud
   apt-get -qq purge nginx-common nginx-full nginx php5 php5-common php5-cgi php5-gd php-xml-parser php5-intl sqlite php5-sqlite php5-curl php-pear php-apc php5-fpm memcached php5-memcache varnish
   apt-get -qq autoremove --purge
   clear
   hint_msg $"Reboot is recommended"
   return
}

case $1 in
   update)
      update_owncloud
      ;;
   install)
      install_owncloud
      ;;
   remove)
      remove_owncloud
      ;;
esac