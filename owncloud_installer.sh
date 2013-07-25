PATH_TO_WEBSERVER="/var/www/cloud"
CREATE_DYNAMIC_HOST=true
SERVER_NAME=""
VERSION=""
STANDARD_VERBOSE_FLAG=""
APT_GET_FLAG="-qq"
WGET_FLAG="-q"
STARTPATH=$PWD
MY_NAME="$0"
DO_MAIN_INSTALL=false
DO_MAIN_UPDATE=false
DO_UNINSTALL=false

function install_nginx_and_other_stuff(){
   echo $"Installing nginx and php..."
   apt-get $APT_GET_FLAG install nginx php5 php5-common php5-cgi php5-gd php-xml-parser php5-intl sqlite php5-sqlite curl libcurl3 php5-curl php-pear php-apc php5-fpm memcached php5-memcache smbclient openssl ssl-cert varnish dphys-swapfile
   echo $"Searching for packages that are no longer needed..."
   apt-get $APT_GET_FLAG autoremove

   clear
   echo -ne $"The next step will create a ssl certificate.\nDon't leave the field 'Common Name' blank.\nHit Enter to continue."
   read tmpvar

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

   if $CREATE_DYNAMIC_HOST; then
      echo $"Creating files in /etc/dhcp/dhclient-exit-hooks.d/..."
      dynamic_hostname
   fi

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

function install_dependencies(){
   echo $"Installing dependencies..." &&
   apt-get $APT_GET_FLAG install dhcp3-client hostname bind9-host coreutils wget
   clear
}

function install_oc(){
   echo $"Decompressing owncloud-$VERSION.tar.bz2..."
   cd $STARTPATH
   tar -xj $STANDARD_VERBOSE_FLAG -f owncloud-$VERSION.tar.bz2
   mkdir -p $STANDARD_VERBOSE_FLAG $PATH_TO_WEBSERVER

   echo $"Copying decompressed files to '$PATH_TO_WEBSERVER'..."
   cp -R $STANDARD_VERBOSE_FLAG owncloud/* $PATH_TO_WEBSERVER

   echo $"Setting permissions for '$PATH_TO_WEBSERVER'..."
   cd $PATH_TO_WEBSERVER
   chown -R $STANDARD_VERBOSE_FLAG www-data:www-data ..
   chmod -R $STANDARD_VERBOSE_FLAG 644 .
   find . -type d -exec chmod $STANDARD_VERBOSE_FLAG 755  {} \;

   if $DATA_TO_EXTERNAL_DISK; then
      echo $"Creating conf.php..."
      create_minimal_php_conf
      mkdir $STANDARD_VERBOSE_FLAG $EXTERNAL_DATA_DIR
      chown -R $STANDARD_VERBOSE_FLAG www-data:www-data $EXTERNAL_DATA_DIR
   fi

   echo $"Cleaning up..."
   cd $STARTPATH
   rm -R $STANDARD_VERBOSE_FLAG owncloud{,*.tar.bz2,.md5}
   service php5-fpm restart
   service nginx restart
}

function dynamic_hostname(){
mkdir -p $STANDARD_VERBOSE_FLAG /etc/dhcp/dhclient-exit-hooks.d/
# Die Dateien sind gezipt und mit base64 codiert um Platz zu sparen
echo "H4sIAEt7hlEAA5VSQW7bMBC88xWTRIgdILIaFD0kgHtwlSK52EbaoIcmMGRxVRGVSYFLtTXQx3cl
W0IbO4dSgEjuzgx3yD07SdbGJlwqdYaPpiKbbegG7Ugo5Iku8/pt+68M2RDTLxPi0rnvPNHJm6tV
6Ti0DCEvG1873nPxyKSx3mJgcu5NHRAcmGQqCT0Xruj2vOVAG1H6dwhjk4W87DDp/BOMLZyXkHEW
shq0kDFq734Y3R19IJTefVhOJJpSTVbzvtDOYLwrEmMuXVMJm+SUTnidcbvmkFXVxYHkYGHcFtLv
LpF9y4y9xFG1QxV5AH0ddxYGnUNU7jw1wVS8A+WNGLYalJdOwEqZAl9xGnnK2NlTnEwxWzzOUzzj
/Pxl5uF2fvtFMk9KhI+lZ/evMmeLxWc8K7FjVV+bp9B4qwqjVFsPjvdLfz83SLcymxz3S2Rae2LG
FJGlnytTr/YR1cOn0bi7mxd5/O7uINYYyRcXeCeRtutiwoiTp0mUJKOLXT3R8FDvd2099O2QGCD/
5+Cu50//UvgDCsDvxlUDAAA=" | base64 -d | gunzip - > /etc/dhcp/dhclient-exit-hooks.d/01_hostname
chmod $STANDARD_VERBOSE_FLAG 544 /etc/dhcp/dhclient-exit-hooks.d/01_hostname

echo "H4sIAF2ehlEAA1WMwQqCQBiE7/sU4ypSge4DhIeIoEt1yGMQq/7mgv0bu2vl22dERJcZPoZv4khV
hpXvhIhRdsbjpl3A1EzUUINqxGgHB/vgdW+HBoZ90H2vg7EstodjuV/tNkUy66wPrK80F4F8QPKd
EBWQEmkKP91lBhlBejWRu5M7v5V88Yc/97RUEopCrfhi+PnJvLbciheb0CQsuQAAAA==" | base64 -d | gunzip - > /etc/dhcp/dhclient-exit-hooks.d/02_nginxconf
chmod $STANDARD_VERBOSE_FLAG 544 /etc/dhcp/dhclient-exit-hooks.d/02_nginxconf
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
   server_name $SERVER_NAME;
   return https://\$server_name\$request_uri;  # enforce https
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
   mkdir -p $STANDARD_VERBOSE_FLAG /srv/http/owncloud/data
   chown $STANDARD_VERBOSE_FLAG www-data:www-data /srv/http/owncloud/data
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
chown $STANDARD_VERBOSE_FLAG www-data:www-data $PATH_TO_WEBSERVER/config/config.php
}


function download_and_check_oc(){
   OWNCLOUD_URL="http://download.owncloud.org/community/owncloud-$VERSION.tar.bz2"
   OWNCLOUD_CHECKSUM_URL="http://download.owncloud.org/community/owncloud-$VERSION.tar.bz2.md5"

   # Download ownCloud archive
   echo $"Downloading owncloud-$VERSION.tar.bz2..."
   wget $WGET_FLAG $OWNCLOUD_URL || (echo $"Download failed" && return 1)
   wget -qO - $OWNCLOUD_CHECKSUM_URL | sed s/-/owncloud-$VERSION.tar.bz2/g > owncloud.md5
   echo -n $"Checking download..."
   md5sum -c owncloud.md5 || (error_msg $"Download failed" && return 1)
}

function pre_check_version(){
   AVAILABLE_VERSIONS=$(wget -qO - http://owncloud.org/releases/Changelog | grep Release |  tr -d 'Relas \"' | tr "\n" ' ')
   for versions in $AVAILABLE_VERSIONS; do
      [ "$versions" == "$VERSION" ] && return
   done
   echo -e $"An error occurred while checking version." && return 1
}

# check and install dependencies
function sys_update(){
   echo $"Updating the operating systems's software (might take a while)..."
   apt-get $APT_GET_FLAG update &&
   apt-get $APT_GET_FLAG upgrade &&
   if [ $? -ne 0 ]; then
      echo $"Update failed."
      echo $"Bye..."
      exit 1
   fi
   clear
}

function main_install(){
   clear
   pre_check_version
   echo $"Installing ownCloud version: $VERSION"
   sys_update
   install_dependencies
   [ "x$SERVER_NAME" == "x" ] && SERVER_NAME=$(host $(ifconfig | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -Ev "127.0.0.1|255|.255" | head -n1) | cut -d ' ' -f 5 | sed -e 's/\.$//')
   [ "x$SERVER_NAME" == "xip" ] && SERVER_NAME=$(ifconfig | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -Ev "127.0.0.1|255|.255" | head -n1)
   echo -e $"This name/IP will be used to set up your ownCloud: $SERVER_NAME\nThis will be the name/IP you have to enter in your webbrowser after the script has finished.\nIs the name correct? If not, restart the script now and select 'use_ip'."
   read -p $"Hit Enter to continue or crtl+c to cancel" tmpvar
   EXTERNAL_DATA_DIR="/mnt/data/owncloudData"

   download_and_check_oc &&
   install_nginx_and_other_stuff &&
   clear &&
   install_oc
}

function main_update(){
   clear
   if [ ! -f $PATH_TO_WEBSERVER/config/config.php ]; then
      error_msg $"ownCloud is not installed properly or wasn't installed by this script and thus can't be updated"
      return 1
   fi
   pre_check_version
   sys_update
   download_and_check_oc

   echo $"Decompressing owncloud-$VERSION.tar.bz2..."
   tar -xj $STANDARD_VERBOSE_FLAG -f owncloud-$VERSION.tar.bz2

   echo $"Copying decompressed files to '$PATH_TO_WEBSERVER'..."
   cp -R $STANDARD_VERBOSE_FLAG owncloud/* $PATH_TO_WEBSERVER

   echo $"Setting permissions for '$PATH_TO_WEBSERVER'..."
   cd $PATH_TO_WEBSERVER
   chown -R $STANDARD_VERBOSE_FLAG www-data:www-data ..
   chmod -R $STANDARD_VERBOSE_FLAG 644 .
   find . -type d -exec chmod $STANDARD_VERBOSE_FLAG 755 {} \;

   echo $"Cleaning up..."
   cd $STARTPATH
   rm -r $STANDARD_VERBOSE_FLAG owncloud{,*.tar.bz2,.md5}
   return
}

function remove_owncloud(){
   clear
   if [ ! -f $PATH_TO_WEBSERVER/config/config.php ]; then
      error_msg $"ownCloud is not installed properly or wasn't installed by this script and thus can't be removed"
      return 1
   fi
   read -p $"Are you sure you want to continue? (y/n): " choice
   [ "$choice" != $"y" ] && return 1
   read -p $"Do you want to remove ownCloud's datadirectory? (y/n)" choice

   DATA_DIR=$(grep datadirectory $PATH_TO_WEBSERVER/config/config.php | cut -d\' -f4)

   if [ "$choice" == $"y" ] && [[ $DATA_DIR != $PATH_TO_WEBSERVER/* ]]; then
      rm -r $STANDARD_VERBOSE_FLAG $DATA_DIR
      rm -r $STANDARD_VERBOSE_FLAG $PATH_TO_WEBSERVER
   elif [ "$choice" == $"y" ] && [[ $DATA_DIR == $PATH_TO_WEBSERVER/* ]]; then
      rm -r $STANDARD_VERBOSE_FLAG $PATH_TO_WEBSERVER
   elif [ "$choice" == $"n" ] && [[ $DATA_DIR != $PATH_TO_WEBSERVER/* ]]; then
      rm -r $STANDARD_VERBOSE_FLAG $PATH_TO_WEBSERVER
   elif [ "$choice" == $"n" ] && [[ $DATA_DIR == $PATH_TO_WEBSERVER/* ]]; then
      find $PATH_TO_WEBSERVER/* -maxdepth 0 ! -name data -exec rm -r $STANDARD_VERBOSE_FLAG {} \;
   fi

   [ -e /etc/dhcp/dhclient-exit-hooks.d/01_hostname ] && rm $STANDARD_VERBOSE_FLAG /etc/dhcp/dhclient-exit-hooks.d/01_hostname
   [ -e /etc/dhcp/dhclient-exit-hooks.d/02_nginxconf ] && rm $STANDARD_VERBOSE_FLAG /etc/dhcp/dhclient-exit-hooks.d/02_nginxconf
   rm -r $STANDARD_VERBOSE_FLAG /srv/http/owncloud
   apt-get $APT_GET_FLAG purge nginx-common nginx-full nginx php5 php5-common php5-cgi php5-gd php-xml-parser php5-intl sqlite php5-sqlite libcurl3 php5-curl php-pear php-apc php5-fpm memcached php5-memcache smbclient ssl-cert varnish
   apt-get $APT_GET_FLAG autoremove --purge
   clear
   hint_msg $"Reboot is recommended"
   return
}

# parse commandline arguments
ARGS=($(getopt -o rvi:u:n: -l "remove-oc,verbose,install:,update:,name:" -n "$MY_NAME" -- "$@" | tr -d \'))
if [ $? -ne 0 ]; then
   usage
   exit 2
fi
i=0
while [ "${ARGS[$i]}" != "--" ]; do

   case "${ARGS[$i]}" in
      -u|--update)
         i=$[$i+1]
         VERSION=${ARGS[$i]}
         DO_MAIN_UPDATE=true
         ;;
      -n|--name)
         i=$[$i+1]
         SERVER_NAME="${ARGS[$i]}"
         CREATE_DYNAMIC_HOST=false
         ;;
      -i|--install)
         i=$[$i+1]
         VERSION=${ARGS[$i]}
         DO_MAIN_INSTALL=true
         ;;
      -v|--verbose)
         STANDARD_VERBOSE_FLAG="-v"
         APT_GET_FLAG=""
         WGET_FLAG="-v"
         ;;
      -r|--remove-oc)
         DO_UNINSTALL=true
         ;;
   esac
   i=$[$i+1]
done


if [ "$VERSION" == "latest" ]; then
   VERSION=$LATEST_VERSION
fi

$DO_MAIN_INSTALL && main_install
$DO_MAIN_UPDATE && main_update
$DO_UNINSTALL && remove_owncloud
