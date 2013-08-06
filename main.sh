#!/bin/bash

# TEXTDOMAIN and TEXTDOMAINDIR are used for i18n
TEXTDOMAIN=apis
TEXTDOMAINDIR=./locale

function print_message(){
   whiptail --title "$1" --msgbox "$2" 30 80
}

function hint_msg(){
   whiptail --title $"HINT" --msgbox "$1" 30 80
}

function error_msg(){
   whiptail --title $"ERROR" --msgbox "$1" 30 80
}

function reboot_prompt(){
   whiptail --msgbox "$1" 30 80 &&
   reboot
}

function user_input(){
   whiptail --title "$1" --inputbox "$2" 30 80 $3 3>&1 1>&2 2>&3
}

function password_box(){
   whiptail --title "$1" --passwordbox "$2" 30 80 $3 3>&1 1>&2 2>&3
}

function yes_no(){
   whiptail --title "$1" --yesno "$2" 30 80 3>&1 1>&2 2>&3
}

function update_or_remove_owncloud(){
   option=$(whiptail --ok-button $"Select" --cancel-button $"Back" --title $"Update/remove ownCloud" --menu $"\nUpdate to latest version of ownCloud\nUse the update function only for updates, not for upgrades. See http://doc.owncloud.org/server/5.0/admin_manual/maintenance/update.html for more details." 30 80 15 \
      update $"Update your ownCloud installation"\
      remove $"Remove ownCloud" 3>&1 1>&2 2>&3)

   if [ "$option" == "update" ]; then
      . owncloud_installer.sh  update
   elif [ "$option" == "remove" ]; then
      . owncloud_installer.sh remove && 
      sed -i 's/OWNCLOUD_INSTALLED.*/OWNCLOUD_INSTALLED=false/' /var/lib/apis/conf
   fi
}

function remove_or_change_samba(){
   option=$(whiptail --ok-button $"Select" --cancel-button $"Back" --title $"Change/remove Samba" --radiolist $"\nUpdates for Samba are done by the system's package management.\nYou can either add more Samba shares or remove Samba." 30 80 15 \
      add $"Add more shares and users" 1\
      remove $"Remove samba" 0 3>&1 1>&2 2>&3)

   if [ "$option" == "add" ];then
      . samba_installer.sh add
   elif [ "$option" == "remove" ]; then
      . samba_installer.sh remove &&
      sed -i 's/SAMBA_INSTALLED.*/SAMBA_INSTALLED=false/' /var/lib/apis/conf
   fi
}

function configure_nfs(){
   option=$(whiptail --ok-button $"Select" --cancel-button $"Back" --title $"Configure NFS" --menu $"\nNote: Updates are not covered by APIS since the package management system manages them." 30 80 15 \
      add-shares $"Add more NFS shares" \
      delete-shares $"Delete NFS shares" \
      add-clients $"Add clients to NFS shares" \
      delete-clients $"Remove clients from configuration files" \
      uninstall $"Uninstall NFS server" 3>&1 1>&2 2>&3)

   case $option in
      uninstall)
	. nfs_installer.sh uninstall &&
	sed -i 's/NFS_INSTALLED.*/NFS_INSTALLED=false/' /var/lib/apis/conf
	;;
      add-clients)
	. nfs_installer.sh add-clients
	;;
      add-shares)
	. nfs_installer.sh add-shares
	;;
      delete-shares)
	. nfs_installer.sh delete-shares
	;;
      delete-clients)
	. nfs_installer.sh delete-clients
	;;
   esac
}

function main(){
   . /var/lib/apis/conf
   choice=$(whiptail --ok-button $"Select" --cancel-button $"Exit" --title "APIS" --menu $"\nAwesome Pi Installation Script\n\nInstall some cool stuff on your Raspberry Pi.\n" 30 88 15 \
      owncloud_setup $"Install/update/remove ownCloud"\
      samba_setup $"Install/remove Samba Server" \
      btsync_setup $"Install/uninstall BitTorrent Sync" \
      nfs_setup $"Install/uninstall/configure Network File System Server" 3>&1 1>&2 2>&3)

   case $choice in
      owncloud_setup)
         if $OWNCLOUD_INSTALLED; then
            update_or_remove_owncloud
            main
            return
         else
            . owncloud_installer.sh install &&
            sed -i 's/OWNCLOUD_INSTALLED.*/OWNCLOUD_INSTALLED=true/' /var/lib/apis/conf
            reboot_prompt $"In a few moments you can finally enjoy your ownCloud.\nThe Raspberry Pi is going to reboot now.\nAfter that open a web browser and navigate to your ownCloud instance. Enter a username and a password. The advanced settings are preconfigured by this script, so don't change them!"
         fi
         ;;
      samba_setup)
         if $SAMBA_INSTALLED; then
            remove_or_change_samba
            main
            return
         else
            . samba_installer.sh install
            sed -i 's/SAMBA_INSTALLED.*/SAMBA_INSTALLED=true/' /var/lib/apis/conf
            main
            return
         fi
         ;;
      btsync_setup)
	if $BTSYNC_INSTALLED; then
	   . btsync_installer.sh uninstall &&
	   sed -i 's/BTSYNC_INSTALLED.*/BTSYNC_INSTALLED=false/' /var/lib/apis/conf
	   main
            return
	else
	   . btsync_installer.sh install &&
	   sed -i 's/BTSYNC_INSTALLED.*/BTSYNC_INSTALLED=true/' /var/lib/apis/conf
            main
            return	   
	fi
	;;
      nfs_setup)
	if $NFS_INSTALLED; then
	   configure_nfs
	   main
            return
	else
	   . nfs_installer.sh install &&
	   sed -i 's/NFS_INSTALLED.*/NFS_INSTALLED=true/' /var/lib/apis/conf
            main
            return	   
	fi
	;;
   esac
}

# check if the script has root permissions
if [ "$(whoami)" != "root" ]; then
   echo $"I need root permissions."
   echo $"Bye..."
   exit 1
fi

if [ ! -f /var/lib/apis/conf ]; then
   mkdir /var/lib/apis
   USE_EXTERNAL_SPACE=true
   . data_to_external_disk.sh
   whiptail --title "APIS" --yesno $"This setup can install and configure a whole bunge of different software eg. Samba, ownCloud...\nDo you want to use a external disk to store datadirectories of ownCloud and Samba on it?" 30 80
   exit_status=$?
   case $exit_status in
      0)
         data_to_external_disk
         if $USE_EXTERNAL_SPACE;then
            echo "DATA_TO_EXTERNAL_DISK=true" > /var/lib/apis/conf
         else
            echo "DATA_TO_EXTERNAL_DISK=false" > /var/lib/apis/conf
         fi
         ;;
      1)
         echo "DATA_TO_EXTERNAL_DISK=false" > /var/lib/apis/conf
         ;;
      *)
         exit
         ;;
   esac
   echo "OWNCLOUD_INSTALLED=false" >> /var/lib/apis/conf
   echo "SAMBA_INSTALLED=false" >> /var/lib/apis/conf
   echo "BTSYNC_INSTALLED=false" >> /var/lib/apis/conf
   echo "NFS_INSTALLED=false" >> /var/lib/apis/conf
fi

main
