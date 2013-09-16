function install_btsync(){
   USERNAME=""
   PASSWORD=""
   COMMA=""

   yes_no $"Confirmation" $"Do you really want to install BitTorrent Sync?\nBy using BitTorrent Sync, you agree to their Privacy Policy and Terms.\nhttp://www.bittorrent.com/legal/privacy\nhttp://www.bittorrent.com/legal/terms-of-use" || return 1
   echo $"Installing BitTorrent Sync..."
   mkdir ./tmp && pushd ./tmp
   echo $"Downloading BitTorrent Sync..."
   wget -q http://btsync.s3-website-us-east-1.amazonaws.com/btsync_arm.tar.gz
   echo $"Unpacking .tar file..."
   tar -xf btsync_arm.tar.gz
   cp btsync /usr/bin/
   popd
   echo $"Removing temporary files..."
   rm -r ./tmp

   print_message $"Create username and password" $"The BitTorrent Sync webinterface can be protected by a dialog that asks for username and password."

   while true; do
      users_name=$(user_input $"Username" $"Enter a username or leave it blank, if you don't want to install a password dialog:")
      if [ -z $users_name ]; then
         break
      else
         USERNAME="      \"login\" : \"$users_name\","
      fi

      users_password=$(password_box $"Password" $"Enter a password for user $users_name: ")
      if [ -z $users_password ]; then
         continue
      fi

      users_password_double_check=$(password_box $"Password" $"Retype the password for user $users_name: ")
      if [ "$users_password_double_check" == "$users_password" ]; then
         PASSWORD="      \"password\" : \"$users_password\""
         COMMA=","
         break
      fi
   done

   cat > /etc/btsync.conf << EOF
{
   "device_name": "Raspberry Pi",
   "listening_port" : 0,                       // 0 - randomize port

   /* storage_path dir contains auxilliary app files
   if no storage_path field: .sync dir created in the directory
   where binary is located.
   otherwise user-defined directory will be used
   */
   "storage_path" : "/home/btsync/sync",

   // location of pid file
   "pid_file" : "/home/btsync/btsync.pid",

   "check_for_updates" : true,
   "use_upnp" : true,                              // use UPnP for port mapping


   /* limits in kB/s
   0 - no limit
   */
   "download_limit" : 0,
   "upload_limit" : 0,

   /* remove "listen" field to disable WebUI
   remove "login" and "password" fields to disable credentials check 
   */
   "webui" :
   {
      "listen" : "0.0.0.0:8888"$COMMA
$USERNAME
$PASSWORD
   },
   "lan_encrypt_data" : false,
   "lan_use_tcp" : true


   /* !!! if you set shared folders in config file WebUI will be DISABLED !!!
   shared directories specified in config file
   override the folders previously added from WebUI.
   */
   /*
   ,
   "shared_folders" :
   [
      {
	//  use --generate-secret in command line to create new secret
	"secret" : "Put_your_secret_here",                   // * required field
	"dir" : "/home/user/bittorrent/sync_test", // * required field

	//  use relay server when direct connection fails
	"use_relay_server" : true,
	"use_tracker" : true, 
	"use_dht" : false,
	"search_lan" : true,
	//  enable sync trash to store files deleted on remote devices
	"use_sync_trash" : true,
	//  specify hosts to attempt connection without additional search     
	"known_hosts" :
	[
	   "192.168.1.2:44444"
	]
      }
   ]
   */

   // Advanced preferences can be added to config file.
   // Info is available in BitTorrent Sync User Guide.

}
EOF

   adduser btsync --system --group --shell /bin/sh
   cp btsync-init-script /etc/init.d/btsync
   chmod 755 /etc/init.d/btsync
   update-rc.d btsync defaults
   service btsync start
   hint_msg $"BitTorrent Sync's webinterface is now available under $IP:8888"
   return 0
}

function uninstall_btsync(){
   if $(yes_no $"Remove BitTorrent Sync" $"Are you sure that you want to uninstall BitTorrent Sync? Datadirectories won't be deleted."); then
      service btsync stop
      rm /usr/bin/btsync
      rm /etc/btsync.conf
      rm /etc/init.d/btsync
      rm -r /opt/btsync
      update-rc.d btsync remove
      return 0
   fi
   return 1
}

case $1 in 
   install)
      install_btsync
      ;;
   uninstall)
      uninstall_btsync
      ;;
esac
