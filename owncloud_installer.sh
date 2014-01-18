WEBSERVER_ROOT="/var/www"
OWNCLOUD_DIR="$WEBSERVER_ROOT/owncloud"
VERSION=""
STARTPATH=$PWD

function install_oc(){
   echo $"Creating /etc/nginx/nginx.conf..."
   create_nginx_conf_files

   echo $"Decompressing owncloud-$VERSION.tar.bz2..."
   tar -xjf /tmp/owncloud-$VERSION.tar.bz2 -C $WEBSERVER_ROOT

   echo $"Setting permissions for '$OWNCLOUD_DIR'..."
   chown -R  www-data:www-data $OWNCLOUD_DIR
   chmod -R  644 $OWNCLOUD_DIR
   find $OWNCLOUD_DIR -type d -exec chmod  755  {} \;

   if $DATA_TO_EXTERNAL_DISK; then
      echo $"Creating conf.php..."
      create_minimal_php_conf
      mkdir  $OC_DATA_DIR
      chown -R  www-data:www-data $OC_DATA_DIR
   fi

   echo $"Cleaning up..."
   rm -R /tmp/owncloud{*.tar.bz2,.md5}

   # add owncloud to NGINX_REQUIRED in /var/lib/apis/conf
   set_var_nginx_required add owncloud

   service nginx restart
}

function create_nginx_conf_files(){
# Based on http://doc.owncloud.org/server/5.0/admin_manual/installation/installation_others.html?highlight=nginx
   sed -i $\d /etc/nginx/sites-available/apis-ssl
   cat >> /etc/nginx/sites-available/apis-ssl << EOF
   #begin_owncloud_config
   location = /owncloud/robots.txt {
      allow all;
      log_not_found off;
      access_log off;
   }

   rewrite ^/owncloud/caldav(.*)$ /owncloud/remote.php/caldav\$1 redirect;
   rewrite ^/owncloud/carddav(.*)$ /owncloud/remote.php/carddav\$1 redirect;
   rewrite ^/owncloud/webdav(.*)$ /owncloud/remote.php/webdav\$1 redirect;

   # The following 2 rules are only needed with webfinger, uncomment them if you need.
   rewrite ^/owncloud/.well-known/host-meta /owncloud/public.php?service=host-meta last;
   rewrite ^/owncloud/.well-known/host-meta.json /owncloud/public.php?service=host-meta-json last;

   rewrite ^/owncloud/.well-known/carddav /owncloud/remote.php/carddav/ redirect;
   rewrite ^/owncloud/.well-known/caldav /owncloud/remote.php/caldav/ redirect;

   rewrite ^(/owncloud/core/doc/[^\/]+/)$ \$1/index.html redirect;

   location /owncloud {
      try_files \$uri \$uri/ index.php;
      location ~ ^(.+?\.php)(/.*)?$ {
         try_files \$1 = 404;

         include fastcgi_params;
         fastcgi_param SCRIPT_FILENAME \$document_root\$1;
         fastcgi_param PATH_INFO \$2;
         fastcgi_param HTTPS on;
         fastcgi_pass php-handler;
      }
   }

   # Optional: set long EXPIRES header on static assets
   location ~* ^/owncloud/.+\.(jpg|jpeg|gif|bmp|ico|png|css|js|swf)$ {
      expires 30d;
      # Optional: Don't log access to assets
      access_log off;
   }
   #end_owncloud_config

}
EOF
}

function create_minimal_php_conf(){
cat > $OWNCLOUD_DIR/config/config.php << EOF
<?php
\$CONFIG = array (
  'datadirectory' => '$OC_DATA_DIR',
  'dbtype' => 'sqlite3',
  'installed' => false,
);
EOF
chown  www-data:www-data $OWNCLOUD_DIR/config/config.php
}

function download_and_check_oc(){
   OWNCLOUD_URL="http://download.owncloud.org/community/owncloud-$VERSION.tar.bz2"
   OWNCLOUD_CHECKSUM_URL="http://download.owncloud.org/community/owncloud-$VERSION.tar.bz2.md5"

   # Download ownCloud archive
   pushd /tmp
   echo $"Downloading owncloud-$VERSION.tar.bz2..."
   wget -q $OWNCLOUD_URL
   if [ $? -ne 0 ]; then
      error_msg $"Download failed"
      return 1
   fi
   wget -qO - $OWNCLOUD_CHECKSUM_URL | sed s/-/owncloud-$VERSION.tar.bz2/g > owncloud.md5
   echo -n $"Checking download..."
   md5sum -c owncloud.md5
   if [ $? -ne 0 ]; then
      error_msg $"Download failed"
      return 1
   fi
   popd
}

# Get latest version from ownCloud's xml updater. This URI is from check() in ownCloud's code ('owncloudroot'/lib/private/updater.php)
function get_latest_version(){
   wget -qO - http://apps.owncloud.com/updater.php?version=5x00x10x1375797810.1234x1375797810.3456xstablex | grep versionstring | grep -Eo "[0-9]{1,2}.[0-9]{1,2}.[0-9]{1,2}([a-z]?)"
}

function install_owncloud(){
   echo $"Getting latest version..."
   VERSION=$(get_latest_version)
   yes_no $"IP address and version" $"After APIS has finished, ownCloud will be available under: $IP/owncloud\nThis version of ownCloud will be installed: $VERSION\nDo you want to continue?" || return 1

   sys_update
   if ! $NGINX_INSTALLED; then
      . nginx_basic_installer.sh install
   fi

   OC_DATA_DIR=$EXTERNAL_DATA_DIR/owncloudData

   download_and_check_oc &&
   install_oc
   print_message $"Almost finished" $"In a few moments you can finally enjoy your ownCloud.\nOpen a web browser and navigate to $IP/owncloud. You will see the installation page of ownCloud, which asks for a username and a password.\n\nIMPORTANT: do not change the advanced settings, because APIS already did that for you!"
   # Create cronjob
   echo '*/5  *  *  *  * php -f /var/www/owncloud/cron.php' | crontab -u www-data -
   return 0
}

function get_installed_version(){
   grep VersionString $OWNCLOUD_DIR/version.php | tr -d " \'\;" | cut -d'=' -f2
}

function update_owncloud(){
   if [ ! -f $OWNCLOUD_DIR/config/config.php ]; then
      error_msg $"ownCloud is not installed properly or wasn't installed by this script and thus can't be updated."
      return 1
   fi
   INSTALLED_VERSION=$(get_installed_version)
   LATEST_VERSION=$(get_latest_version)
   if [ "$LATEST_VERSION" == "$INSTALLED_VERSION" ]; then
      error_msg $"Latest version is already installed."
      return 1
   fi
   sys_update
   download_and_check_oc || return 1

   echo $"Decompressing owncloud-$VERSION.tar.bz2..."
   tar -xjf /tmp/owncloud-$VERSION.tar.bz2 -C $WEBSERVER_ROOT

   echo $"Setting permissions for '$OWNCLOUD_DIR'..."
   chown -R  www-data:www-data $OWNCLOUD_DIR
   chmod -R  644 $OWNCLOUD_DIR
   find $OWNCLOUD_DIR -type d -exec chmod  755  {} \;

   echo $"Cleaning up..."
   rm -R /tmp/owncloud{*.tar.bz2,.md5}
   return 0
}

function remove_owncloud(){
   if [ ! -f $OWNCLOUD_DIR/config/config.php ]; then
      error_msg $"ownCloud is not installed properly or wasn't installed by this script and thus can't be removed."
      return 1
   fi
   yes_no $"Starting uninstaller" $"Are you sure you want to continue?" || return 1

   if yes_no $"Datadirectory" $"Do you want to remove ownCloud's datadirectory?"; then
      choice="y"
   else
      choice="n"
   fi

   DATA_DIR=$(grep datadirectory $OWNCLOUD_DIR/config/config.php | cut -d\' -f4)

   if [ "$choice" == "y" ] && [[ $DATA_DIR != $OWNCLOUD_DIR/* ]]; then
      rm -r  $DATA_DIR
      rm -r  $OWNCLOUD_DIR
   elif [ "$choice" == "y" ] && [[ $DATA_DIR == $OWNCLOUD_DIR/* ]]; then
      rm -r  $OWNCLOUD_DIR
   elif [ "$choice" == "n" ] && [[ $DATA_DIR != $OWNCLOUD_DIR/* ]]; then
      rm -r  $OWNCLOUD_DIR
   elif [ "$choice" == "n" ] && [[ $DATA_DIR == $OWNCLOUD_DIR/* ]]; then
      find $OWNCLOUD_DIR/* -maxdepth 0 ! -name data -exec rm -r  {} \;
   fi

   # remove owncloud from NGINX_REQUIRED
   set_var_nginx_required remove owncloud

   # If any other program depends on nginx, remove owncloud from nginx config
   # else remove nginx
   if [ -n "$NGINX_REQUIRED" ] ; then
      remove_parts_from_config_files '#begin_owncloud_config' '#end_owncloud_config' '/etc/nginx/sites-available/apis-ssl'
      service nginx restart
   else
      . nginx_basic_installer.sh uninstall
   fi
   return 0
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
