function install_ampache(){
   yes_no $"IP address" $"After APIS has finished, Ampache will be available under: $IP/ampache\nDo you really want to install Ampache?" || return 1
   #echo "CREATE DATABASE ampacheBase; GRANT ALL ON ampacheBase.* TO ampacheUser@localhost IDENTIFIED BY 'password'" | mysql -u root -p
   sys_update
   if ! $NGINX_INSTALLED; then
      . nginx_basic_installer.sh install
   fi

   sed -i $\d /etc/nginx/sites-available/apis-ssl
   cat >> /etc/nginx/sites-available/apis-ssl << EOF
   #begin_ampache_config
   location ^~ /ampache/play/ {
      return http://\$host\$request_uri;
   }

   location /ampache {
      try_files \$uri \$uri/ index.php;
      location ~ \.php(/|$) {
         try_files \$uri = 404;
         fastcgi_pass 127.0.0.1:7659;
         fastcgi_index index.php;
         include fastcgi_params;
      }
   }
   #end_ampache_config

}
EOF
   sed -i $\d /etc/nginx/sites-available/apis
   cat >> /etc/nginx/sites-available/apis << EOF
   #begin_ampache_config
   location /ampache/play {
      location ~ \.php {
         try_files \$uri = 404;
         fastcgi_pass 127.0.0.1:7659;
         fastcgi_index index.php;
         include fastcgi_params;
      }
   }
   #end_ampache_config

}
EOF

   wget https://github.com/ampache/ampache/archive/master.tar.gz
   tar -xf master.tar.gz
   mv ampache-master/ ampache
   mkdir -p /var/www
   cp -r ampache /var/www
   chown -R www-data:www-data /var/www/ampache
   rm -r master.tar.gz ampache

   # See main.sh for details on set_var_nginx_required
   set_var_nginx_required add ampache
   service nginx restart
   hint_msg $"It is highly recommended to run 'mysql_secure_installation' from the terminal after APIS has finished!"
   return
}

function uninstall_ampache(){
   yes_no $"Uninstaller" $"Do you really want to uninstall Ampache?" || return 1
   rm -r /var/www/ampache

   # If any other program depends on nginx, remove ampache from nginx config
   # else remove nginx
   set_var_nginx_required remove ampache
   if [ -n "$NGINX_REQUIRED" ]; then
      remove_parts_from_config_files '#begin_ampache_config' '#end_ampache_config' '/etc/nginx/sites-available/apis-ssl'
      remove_parts_from_config_files '#begin_ampache_config' '#end_ampache_config' '/etc/nginx/sites-available/apis'
      service nginx restart
   else
      . nginx_basic_installer.sh uninstall
   fi
   return 0
}

function upgrade_ampache(){
   yes_no $"Upgrade Ampache" $"Install latest version from github.com.\nAre you sure that you want to upgrade Ampache?" || return 1
   mv /var/www/ampache /var/www/ampache.old
   wget https://github.com/ampache/ampache/archive/master.tar.gz
   tar -xf master.tar.gz
   mv ampache-master/ ampache
   cp -r ampache /var/www
   cp /var/www/ampache.old/config/ampache.cfg.php /var/www/ampache/config/ampache.cfg.php
   chown -R www-data:www-data /var/www/ampache
   rm -r master.tar.gz ampache /var/www/ampache.old

}
case $1 in
   update)
      upgrade_ampache
      ;;
   install)
      install_ampache
      ;;
   uninstall)
      uninstall_ampache
      ;;
esac
