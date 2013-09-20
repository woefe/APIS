function create_pyload_conf(){
DIRECTORY=$1
mkdir -p $DIRECTORY
echo -n $DIRECTORY > /usr/share/pyload/module/config/configdir
cat > $DIRECTORY/pyload.conf << EOF
version: 1 

remote - "Remote":
        bool nolocalauth : "No authentication on local connections" = True
        bool activated : "Activated" = True
        int port : "Port" = 7227
        ip listenaddr : "Adress" = 0.0.0.0

log - "Log":
        int log_size : "Size in kb" = 100
        folder log_folder : "Folder" = Logs
        bool file_log : "File Log" = True
        int log_count : "Count" = 5
        bool log_rotate : "Log Rotate" = True

permission - "Permissions":
        str group : "Groupname" = pyload
        bool change_dl : "Change Group and User of Downloads" = False
        bool change_file : "Change file mode of downloads" = False
        str user : "Username" = pyload
        str file : "Filemode for Downloads" = 0664
        bool change_group : "Change group of running process" = False
        str folder : "Folder Permission mode" = 0755
        bool change_user : "Change user of running process" = False

general - "General":
        en;de;fr;it;es;nl;sv;ru;pl;cs;sr;pt_BR language : "Language" = ${LANG:0:2}
        folder download_folder : "Download Folder" = Downloads
        bool checksum : "Use Checksum" = False
        bool folder_per_package : "Create folder for each package" = True
        bool debug_mode : "Debug Mode" = False
        int min_free_space : "Min Free Space (MB)" = 200
        int renice : "CPU Priority" = 0

ssl - "SSL":
        file cert : "SSL Certificate" = ssl.crt
        bool activated : "Activated" = False
        file key : "SSL Key" = ssl.key

webinterface - "Webinterface":
        str template : "Template" = default
        bool activated : "Activated" = True
        str prefix : "Path Prefix" = 
        builtin;threaded;fastcgi;lightweight server : "Server" = builtin
        ip host : "IP" = 0.0.0.0
        bool https : "Use HTTPS" = False
        int port : "Port" = 8910

proxy - "Proxy":
        str username : "Username" = None
        bool proxy : "Use Proxy" = False
        str address : "Address" = "localhost"
        password password : "Password" = None
        http;socks4;socks5 type : "Protocol" = http
        int port : "Port" = 7070

reconnect - "Reconnect":
        time endTime : "End" = 0:00
        bool activated : "Use Reconnect" = False
        str method : "Method" = None
        time startTime : "Start" = 0:00

download - "Download":
        int max_downloads : "Max Parallel Downloads" = 3
        bool limit_speed : "Limit Download Speed" = False
        str interface : "Download interface to bind (ip or Name)" = None
        bool skip_existing : "Skip already existing files" = False
        int max_speed : "Max Download Speed in kb/s" = -1
        bool ipv6 : "Allow IPv6" = False
        int chunks : "Max connections for one download" = 3

downloadTime - "Download Time":
        time start : "Start" = 0:00
        time end : "End" = 0:00
EOF
chown -R pyload:pyload $DIRECTORY
}

function create_smb_share(){
   echo $"Installing Samba..."
   apt-get -qq install samba-common samba-common-bin samba tdb-tools
   hint_msg $"APIS will create samba shares that are protected by a username and password."
   clear
   while true; do
      read -p $"Enter a username: " username &&
      adduser --no-create-home --disabled-login --shell /bin/false --ingroup pyload $username
      break
   done
   while true; do
      smbpasswd -a $username && break
   done
   
   cat >> /etc/samba/smb.conf << EOF
#begin_pyload_config
[pyLoadDownloads]
comment = pyLoad Downloads 
path = $CONFDIR/Downloads
available = yes
browsable = yes
guest ok = no
writable = yes
force user = $username
force group = pyload
valid users = $username
#end_pyload_config

EOF
}

function install_pyload(){
   yes_no $"Confirmation" $"Do you really want to install pyLoad?" || return 1

   # Change NONFREE_DEB_SRC to use this installer on other architecture than ARM
   NONFREE_DEB_SRC='deb-src http://mirrordirector.raspbian.org/raspbian/ wheezy main contrib non-free rpi'
   [ $(grep -q "$NONFREE_DEB_SRC" /etc/apt/sources.list) ] || echo $NONFREE_DEB_SRC >> /etc/apt/sources.list
   sys_update
   apt-get -qq install python-crypto python-pycurl python-imaging python-beaker tesseract-ocr tesseract-ocr-eng gocr zip unzip rhino python-openssl python-django
   apt-get -qq remove unrar*
   mkdir unrar_builddir && pushd unrar_builddir
   apt-get -qq build-dep unrar-nonfree 
   apt-get -qq source -b unrar-nonfree
   dpkg -i unrar*.deb
   popd
   rm -r unrar_builddir
   wget http://download.pyload.org/pyload-cli-v0.4.9-all.deb
   dpkg -i pyload-cli-v0.4.9-all.deb
   rm pyload-cli-v0.4.9-all.deb
   adduser pyload --system --group --shell /bin/sh
   if $DATA_TO_EXTERNAL_DISK; then
      CONFDIR=$EXTERNAL_DATA_DIR/pyload
   else
      CONFDIR=/home/pyload/pyload-conf
   fi
   create_pyload_conf $CONFDIR
   print_message $"Set up pyLoad user" $"PyLoads webinterface is protected by a password dialog. Create a new user with pyLoad's user management, that will be started now. Hit enter to continue!"
   clear
   sudo -u pyload pyLoadCore --user
   cp pyload-init-script /etc/init.d/pyload
   update-rc.d pyload defaults
   service pyload start

   if yes_no $"Create a Samba share" $"All downloaded files will be stored locally on your Raspberry Pi. Do want APIS to create a Samba (Windows) share to easily access your downloads?"; then
      create_smb_share
   fi

   hint_msg $"PyLoad's webinterface is now available: $IP:8910\nStart/stop/restart pyLoad with the webinterface or following command:\n   sudo service pyload start/stop/restart"
   return 0
}

function uninstall_pyload(){
   yes_no $"Confirmation" $"Do you really want to uninstall pyLoad download manager" || return 1
   service pyload stop
   apt-get -qq purge pyload-cli
   deluser --remove-all-files pyload 2> /dev/null
   rm -r /usr/share/pyload
   remove_parts_from_config_files '#begin_pyload_config' '#end_pyload_conf' '/etc/samba/smb.conf'
   return 0
}

case $1 in
   install)
      install_pyload
      ;;
   uninstall)
      uninstall_pyload
      ;;
esac



