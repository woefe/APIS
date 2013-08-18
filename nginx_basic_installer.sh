function install_nginx(){
   echo $"Installing nginx and php..."
   apt-get -qq install nginx php5 php5-common php5-cgi php5-gd mysql-server php5-mysql php-xml-parser php5-intl sqlite php5-sqlite curl libcurl3 php5-curl php-pear php-apc php5-fpm memcached php5-memcache smbclient openssl ssl-cert varnish dphys-swapfile
   echo $"Searching for packages that are no longer needed..."
   apt-get -qq autoremove

   print_message $"SSL-Certificate" $"The next step will create a ssl certificate.\nDon't leave the field 'Common Name' blank.\nHit Enter to continue."
   clear
   mkdir -p /etc/nginx/ssl && pushd /etc/nginx/ssl
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
   popd
   
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
   client_max_body_size 1G; # set max upload size
   root /var/www;
   index index.php index.html;
   fastcgi_buffers 64 4K;
   include /etc/nginx/conf.d/*.conf;
   include /etc/nginx/sites-enabled/*;
}
EOF

   cat > /etc/nginx/sites-available/apis << EOF
server {
   listen 80;
   # Deny direct access
   location ~ ^/.+(bin|sql|data|config|\.ht|db_structure\.xml|README) {
      deny all;
   }

   location / {
      return https://\$host\$request_uri;
   }

}
EOF

   cat > /etc/nginx/sites-available/apis-ssl << EOF
server {
   listen 443 ssl;
   ssl_certificate /etc/nginx/ssl/server.crt;
   ssl_certificate_key /etc/nginx/ssl/server.key;

   # Deny direct access
   location ~ ^/.+(bin|sql|data|config|\.ht|db_structure\.xml|README) {
      deny all;
   }

}
EOF

   ensure_key_value "cgi.fix_pathinfo" "=" "0" /etc/php5/fpm/php.ini
   ensure_key_value "listen" "=" "127.0.0.1:7659" /etc/php5/fpm/pool.d/www.conf
   ensure_key_value "upload_max_filesize" "=" "1000M" /etc/php5/fpm/php.ini
   ensure_key_value "post_max_size" "=" "1100M" /etc/php5/fpm/php.ini
   ensure_key_value "memory_limit" "=" "256M" /etc/php5/fpm/php.ini
   ensure_key_value "upload_tmp_dir" "=" "/srv/http/phpTmpUpload" /etc/php5/fpm/php.ini

   mkdir -p /srv/http/phpTmpUpload
   chown  www-data:www-data /srv/http/phpTmpUpload
   mkdir /var/www
   echo $"Editing /etc/dphys-swapfile..."
   cat > /etc/dphys-swapfile << EOF
CONF_SWAPSIZE=768

EOF
   dphys-swapfile setup
   dphys-swapfile swapon

   rm /etc/nginx/sites-enabled/default
   ln -s /etc/nginx/sites-available/apis-ssl /etc/nginx/sites-enabled
   ln -s /etc/nginx/sites-available/apis /etc/nginx/sites-enabled
   service php5-fpm restart
   service nginx restart
   sed -i 's/NGINX_INSTALLED.*/NGINX_INSTALLED=true/' /var/lib/apis/conf
}

function uninstall_nginx(){
   apt-get -qq purge nginx nginx-common php5 php5-common php5-cgi php5-gd mysql-server php5-mysql php-xml-parser php5-intl sqlite php5-sqlite php5-curl php-pear php-apc php5-fpm memcached php5-memcache varnish
   apt-get -qq autoremove --purge
   rm -r /srv/http/phpTmpUpload
   hint_msg $"Reboot is recommended!"
   sed -i 's/NGINX_INSTALLED.*/NGINX_INSTALLED=false/' /var/lib/apis/conf
}

case $1 in 
   install)
      install_nginx
      ;;
   uninstall)
      uninstall_nginx
      ;;
esac