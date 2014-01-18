# TODO get latest version from the internet
LATEST_VERSION=2.1.3

function install_seafile(){
   yes_no $"Confirmation" $"Do you really want to install Seafile?" || return 1
   sys_update

   if ! $NGINX_INSTALLED; then
      . nginx_basic_installer.sh install
   fi
   apt-get -qq install python2.7 python-setuptools python-simplejson python-imaging python-flup sqlite3
   set_var_nginx_required add seafile

   # create nginx config
   sed -i $\d /etc/nginx/sites-available/apis-ssl
   cat >> /etc/nginx/sites-available/apis-ssl << EOF
   #begin_seafile_config
   location /seafile {
      fastcgi_pass    127.0.0.1:8000;
      fastcgi_param   SCRIPT_FILENAME     \$document_root\$fastcgi_script_name;
      fastcgi_param   PATH_INFO           \$fastcgi_script_name;

      fastcgi_param   SERVER_PROTOCOL     \$server_protocol;
      fastcgi_param   QUERY_STRING        \$query_string;
      fastcgi_param   REQUEST_METHOD      \$request_method;
      fastcgi_param   CONTENT_TYPE        \$content_type;
      fastcgi_param   CONTENT_LENGTH      \$content_length;
      fastcgi_param   SERVER_ADDR         \$server_addr;
      fastcgi_param   SERVER_PORT         \$server_port;
      fastcgi_param   SERVER_NAME         \$server_name;
      fastcgi_param   HTTPS               on; # enable this line only if https is used
      access_log      /var/log/nginx/seahub.access.log;
      error_log       /var/log/nginx/seahub.error.log;
   }

   location /seafmedia {
      rewrite ^/seafmedia(.*)$ /media\$1 break;
      root /home/seafile/seafile-server-$LATEST_VERSION/seahub;
   }
   location /seafhttp {
      rewrite ^/seafhttp(.*)$ \$1 break;
      proxy_pass http://127.0.0.1:8082;
      client_max_body_size 0;
    }
   #end_seafile_config

}
EOF
   # create seafile user
   adduser seafile --system --group --shell /bin/sh
   pushd /home/seafile

   # use 'x86-64' for testing on a VM
   local ARCH=pi
   wget http://seafile.googlecode.com/files/seafile-server_$LATEST_VERSION\_$ARCH.tar.gz
   tar -xf seafile-server_$LATEST_VERSION\_$ARCH.tar.gz
   rm seafile-server_$LATEST_VERSION\_$ARCH.tar.gz
   chown -R seafile:seafile seafile-server-$LATEST_VERSION
   popd

   hint_msg $"Seafile's setup script will be started now. You will need your IP address or your hostname. Your IP address is: $IP\nYou may want to write down your IP adress. Try to use the default settings as far as possible!\nIf you are using an external HDD you might want to change Seafile's datadirectory to '/mnt/data/seafile'"
   clear
   sudo -u seafile -H bash -l -c "/home/seafile/seafile-server-$LATEST_VERSION/setup-seafile.sh"

   cat >> /home/seafile/seahub_settings.py << EOF
SERVE_STATIC = False
HTTP_SERVER_ROOT = 'https://$IP/seafhttp'
MEDIA_URL = '/seafmedia/'
SITE_ROOT = '/seafile/'
EOF
   SEAFILE_DATA_DIR=$(cat /home/seafile/ccnet/seafile.ini)
   cat >> $SEAFILE_DATA_DIR/seafile.conf << EOF
max_upload_size=1000
max_download_dir_size=1000
EOF

   ensure_key_value "SERVICE_URL" " = " "https://$IP/seafile" "/home/seafile/ccnet/ccnet.conf"
   cp seafile-init-script /etc/init.d/seafile
   ensure_key_value "APP_VERSION" "=" "$LATEST_VERSION" "/etc/init.d/seafile"
   chmod +x /etc/init.d/seafile
   update-rc.d seafile defaults
   service seafile start
   service nginx restart
   return 0
}

function get_upgrade_type(){
   local INSTALLED_VERSION="$1"
   local LATEST_VERSION="$2"

   if [ ${INSTALLED_VERSION:2:1} -ne ${LATEST_VERSION:2:1} ]; then
      if [ $[${INSTALLED_VERSION:2:1}+1] -eq ${LATEST_VERSION:2:1} ]; then
         echo continuous
         return
      else
         echo noncontinuous
         return
      fi
   fi
   [ ${INSTALLED_VERSION:4:1} -ne ${LATEST_VERSION:4:1} ] && echo minor
}

function upgrade_seafile(){
   local INSTALLED_VERSION=$(grep -E "^APP_VERSION=" /etc/init.d/seafile | grep -Eo [0-9].[0-9].[0-9])

   if [ $INSTALLED_VERSION ==  $LATEST_VERSION ]; then
      error_msg $"Latest version is already installed."
      return 1
   fi
   yes_no $"Confirmation" $"Do you really want to update Seafile?" || return 1
   service seafile stop

   pushd /home/seafile

   # use 'x86-64' for testing on a VM
   local ARCH=pi
   wget http://seafile.googlecode.com/files/seafile-server_$LATEST_VERSION\_$ARCH.tar.gz
   tar -xf seafile-server_$LATEST_VERSION\_$ARCH.tar.gz
   rm seafile-server_$LATEST_VERSION\_$ARCH.tar.gz
   chown -R seafile:seafile seafile-server-$LATEST_VERSION
   popd

   case $(get_upgrade_type "$INSTALLED_VERSION" "$LATEST_VERSION") in
      minor)
         sudo -u seafile -H bash -l -c "/home/seafile/seafile-server-$LATEST_VERSION/upgrade/minor-upgrade.sh"
         ;;
      continuous)
         sudo -u seafile -H bash -l -c "/home/seafile/seafile-server-$LATEST_VERSION/upgrade/upgrade_${INSTALLED_VERSION:0:3}_${LATEST_VERSION:0:3}.sh"
         ;;
      noncontinuous)
         for i in $(seq ${INSTALLED_VERSION:2:1} $[${LATEST_VERSION:2:1}-1]); do
            sudo -u seafile -H bash -l -c "/home/seafile/seafile-server-$LATEST_VERSION/upgrade/upgrade_1.${i}_1.$[$i+1].sh"
         done
         ;;
   esac
   ensure_key_value "APP_VERSION" "=" "$LATEST_VERSION" /etc/init.d/seafile
   sed -i s@root\ /home/seafile/seafile-server.*@root\ /home/seafile/seafile-server-$LATEST_VERSION/seahub\;@ /etc/nginx/sites-available/apis-ssl
   service nginx restart
   service seafile start
}

function uninstall_seafile(){
   yes_no $"Confirmation" $"Are you sure that you want to remove seafile?" || return 1
   service seafile stop
   rm /etc/init.d/seafile
   update-rc.d seafile remove

   deluser --remove-all-files seafile
   delgroup seafile
   # remove seafile from NGINX_REQUIRED
   set_var_nginx_required remove seafile

   # If any other program depends on nginx, remove seafile from nginx config
   # else remove nginx
   if [ -n "$NGINX_REQUIRED" ]; then
      remove_parts_from_config_files '#begin_seafile_config' '#end_seafile_config' '/etc/nginx/sites-available/apis-ssl'
      service nginx restart
   else
      . nginx_basic_installer.sh uninstall
   fi
}

case $1 in
   install)
      install_seafile
      ;;
   upgrade)
      upgrade_seafile
      ;;
   uninstall)
      uninstall_seafile
      ;;
esac
