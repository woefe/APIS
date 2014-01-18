#!/bin/bash

# How to add more installers:
# 1. Add a new _installer file in APIS/ e.g: foo_installer.sh
# 2. Adjust main() in main.sh
# 3. Create a submenu function in main.sh, if necessary. E.g: configure_foo()
# 4. Make sure to add a new variable to /var/lib/apis/conf and the updater. E.g FOO_INSTALLED
# 5. Make sure to change FOO_INSTALLED in /var/lib/apis/conf if foo is installed/uninstalled

# TEXTDOMAIN and TEXTDOMAINDIR are used for i18n
TEXTDOMAIN=apis
TEXTDOMAINDIR=./locale

# $IP contains your IP address
IP=$(ifconfig | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -Ev "127.0.0.1|255|.255" | head -n1)
if [ "$IP" == "" ]; then
   echo -e $"Something is wrong with your network config!\nCould not retrieve your IP Address..."
   exit 1
fi

# Some functions to make whiptail esier to use
# How to use these functions in foo_installer.sh:
#
# print_message "title" "your text"
# hint_msg "your text"
# error_msg "your text"
# reboot_prompt "your text"
#
# user_input and password_box write the user's input to stdout.
# This makes it easy to write the user's input to a variable, like:
# var=$(user_input "title" "your text" "some preset text (optional)")
# var2=$(password_box "title" "your text" "some preset text (optional)")
#
# yes_no will return a zero exitstatus if the question was answered with 'yes'
# and will return a nonzero exitstatus if the answer was 'no'; example:
# if yes_no "title" "your question"; then
#    echo "Answer: yes"
# else
#    echo "Answer: no"
# fi
function print_message(){
   whiptail --title "$1" --msgbox "$2" 30 90
}

function hint_msg(){
   whiptail --title $"HINT" --msgbox "$1" 30 90
}

function error_msg(){
   whiptail --title $"ERROR" --msgbox "$1" 30 90
}

function reboot_prompt(){
   whiptail --msgbox "$1" 30 90 &&
   reboot
}

function user_input(){
   whiptail --title "$1" --inputbox "$2" 30 90 "$3" 3>&1 1>&2 2>&3
}

function password_box(){
   whiptail --title "$1" --passwordbox "$2" 30 90 $3 3>&1 1>&2 2>&3
}

function yes_no(){
   whiptail --title "$1" --yesno "$2" 30 90 3>&1 1>&2 2>&3
}

# When installing foo you probably have to edit some config files.
# Here's a function to make it easier to edit those files.
# Example/usage: ensure_key_value "cgi.fix_pathinfo" "=" "0" /etc/php5/fpm/php.ini
function ensure_key_value(){
   key=$1
   separator=$2
   value=$3
   file=$4
   linenumber=$(grep -n "$key$separator" $file | cut -d: -f1)
   if [ -z $linenumber ]; then
      linenumber=$(grep -n "$key $separator" $file | cut -d: -f1)
      [ -z $linenumber ] && echo $"ERROR: key '$key' doesn't exist in '$file'." && return 1
   fi
   if [ "$(sed -n $linenumber\p $file)" != "$key$separator$value" ]; then
      sed -i $linenumber\c\\"$key$separator$value" $file
   fi
   return
}

# NGINX_REQUIRED contains all names of programs installed by APIS that depend on the nginx webserver
# If foo uses nginx, the install_foo() function should add 'foo' to NGINX_REQUIRED.
# Example:
#
# function install_foo(){
#    ...
#    set_var_nginx_required add foo
#    ...
# }
# function uninstall_foo(){
#    ...
#    set_var_nginx_required remove foo
#    ...
# }
function set_var_nginx_required(){
   case $1 in
      add)
         local linenumber=$(grep -n "NGINX_REQUIRED" /var/lib/apis/conf | cut -d: -f1)
         sed -i $linenumber\s/\'$/\ $2\'/ /var/lib/apis/conf
         ;;
      remove)
         local linenumber=$(grep -n "NGINX_REQUIRED" /var/lib/apis/conf | cut -d: -f1)
         sed -i $linenumber\s/\ $2// /var/lib/apis/conf
         ;;
      *)
         echo "ERROR while setting NGINX_REQUIRED"
   esac
   # source file to make changes available
   . /var/lib/apis/conf
}

# A uninstall_foo() function may need to remove complete blocks from config files.
# This function makes it less complicated to remove blocks.
# Usage:
# remove_parts_from_config_files "beginning marker (e.g. comment)" "ending marker" "/path/to/config/file"
# Example:
# remove_parts_from_config_files '#begin_owncloud_config' '#end_owncloud_config' '/etc/nginx/sites-available/apis-ssl'
function remove_parts_from_config_files(){
   begin_line=$(grep -n "$1" "$3" | cut -d: -f1)
   end_line=$(grep -n  "$2" "$3" | cut -d: -f1)
   sed -i $begin_line,$end_line\d "$3"
}

# Use this function to apt-get update and upgrade raspbian
function sys_update(){
   echo $"Updating the operating systems's software (might take a while)..."
   apt-get -qq update &&
   apt-get -qq upgrade &&
   apt-get -qq autoremove
   if [ $? -ne 0 ]; then
      echo $"Update failed."
      echo $"Bye..."
      return 1
   fi
}

# ownCloud submenu
function update_or_remove_owncloud(){
   option=$(whiptail --ok-button $"Select" --cancel-button $"Back" --title $"Update/remove ownCloud" --menu $"\nUpdate to latest version of ownCloud\nUse the update function only for updates, not for upgrades. See http://doc.owncloud.org/server/5.0/admin_manual/maintenance/update.html for more details." 30 90 15 \
      update $"Update your ownCloud installation"\
      remove $"Remove ownCloud" 3>&1 1>&2 2>&3)

   if [ "$option" == "update" ]; then
      . owncloud_installer.sh  update
   elif [ "$option" == "remove" ]; then
      . owncloud_installer.sh remove &&
      sed -i 's/OWNCLOUD_INSTALLED.*/OWNCLOUD_INSTALLED=false/' /var/lib/apis/conf
   fi
}

# Samba submenu
function remove_or_change_samba(){
   option=$(whiptail --ok-button $"Select" --cancel-button $"Back" --title $"Change/remove Samba" --menu $"\nUpdates for Samba are done by the system's package management.\nYou can either add more Samba shares or remove Samba." 30 90 15 \
      add $"Add more shares and users" \
      remove $"Remove samba" 3>&1 1>&2 2>&3)

   if [ "$option" == "add" ];then
      . samba_installer.sh add
   elif [ "$option" == "remove" ]; then
      . samba_installer.sh remove &&
      sed -i 's/SAMBA_INSTALLED.*/SAMBA_INSTALLED=false/' /var/lib/apis/conf
   fi
}

# NFS submenu
function configure_nfs(){
   option=$(whiptail --ok-button $"Select" --cancel-button $"Back" --title $"Configure NFS" --menu $"\nNote: Updates are not covered by APIS since the package management system manages them." 30 90 15 \
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

# Ampache submenu
function configure_ampache(){
   option=$(whiptail --ok-button $"Select" --cancel-button $"Back" --title $"Update/uninstall Ampache" --menu $"Remove Ampache or get latest version from github." 30 90 15 \
      uninstall $"Uninstall Ampache Server" \
      update $"Update Ampache Server" 3>&1 1>&2 2>&3)

   if [ "$option" == "uninstall" ];then
      . ampache_installer.sh uninstall &&
      sed -i 's/AMPACHE_INSTALLED.*/AMPACHE_INSTALLED=false/' /var/lib/apis/conf
   elif [ "$option" == "update" ]; then
      . ampache_installer.sh update
   fi
}

# Seafile submenu
function configure_seafile(){
   option=$(whiptail --ok-button $"Select" --cancel-button $"Back" --title $"Update/uninstall Seafile" --menu $"Remove Seafile or install latest version" 30 90 15 \
      uninstall $"Uninstall Seafile Server" \
      upgrade $"Update Seafile Server" 3>&1 1>&2 2>&3)

   if [ "$option" == "uninstall" ];then
      . seafile_installer.sh uninstall &&
      sed -i 's/SEAFILE_INSTALLED.*/SEAFILE_INSTALLED=false/' /var/lib/apis/conf
   elif [ "$option" == "upgrade" ]; then
      . seafile_installer.sh upgrade
   fi
}

function main(){
   . /var/lib/apis/conf
   choice=$(whiptail --ok-button $"Select" --cancel-button $"Exit" --title "APIS" --menu $"\nAwesome Pi Installation Script\n\nInstall some cool stuff on your Raspberry Pi.\n" 30 90 15 \
      owncloud_setup $"Install/update/remove ownCloud"\
      samba_setup $"Install/remove Samba Server" \
      btsync_setup $"Install/uninstall BitTorrent Sync" \
      nfs_setup $"Install/uninstall/configure Network File System Server" \
      ampache_setup $"Install/upgrade/uninstall Ampache Streaming Server" \
      seafile_setup $"Install/upgrade/uninstall Seafile Cloud Service" \
      pyload_setup $"Install/uninstall pyLoad download manager" 3>&1 1>&2 2>&3)

   case $choice in
      owncloud_setup)
         if $OWNCLOUD_INSTALLED; then
            update_or_remove_owncloud
            main
            return
         else
            . owncloud_installer.sh install &&
            sed -i 's/OWNCLOUD_INSTALLED.*/OWNCLOUD_INSTALLED=true/' /var/lib/apis/conf
            main
            return
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
      ampache_setup)
         if $AMPACHE_INSTALLED; then
            configure_ampache
            main
            return
         else
            . ampache_installer.sh install &&
            sed -i 's/AMPACHE_INSTALLED.*/AMPACHE_INSTALLED=true/' /var/lib/apis/conf
            main
            return
         fi
         ;;
      seafile_setup)
         if $SEAFILE_INSTALLED; then
            configure_seafile
            main
            return
         else
            . seafile_installer.sh install &&
            sed -i 's/SEAFILE_INSTALLED.*/SEAFILE_INSTALLED=true/' /var/lib/apis/conf
            main
            return
         fi
         ;;
      pyload_setup)
         if $PYLOAD_INSTALLED; then
            . pyload_installer.sh uninstall &&
            sed -i 's/PYLOAD_INSTALLED.*/PYLOAD_INSTALLED=false/' /var/lib/apis/conf
         else
            . pyload_installer.sh install &&
            sed -i 's/PYLOAD_INSTALLED.*/PYLOAD_INSTALLED=true/' /var/lib/apis/conf
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

# If APIS runs the first time '/var/lib/apis/conf' won't exist
# Ask for external storage and write '/var/lib/apis/conf'
# In '/var/lib/apis/conf' APIS will save which components are installed and which are not
if [ ! -f /var/lib/apis/conf ]; then
   echo $"Checking for locale en_US.UTF-8..."
   grep -Eq "^# en_US.UTF-8 UTF-8$" /etc/locale.gen && sed -i -e "s/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" /etc/locale.gen && locale-gen
   mkdir /var/lib/apis
   DATA_TO_EXTERNAL_DISK=true
   yes_no "APIS" $"APIS can install and configure a whole bunge of different software eg. Samba, ownCloud, ... Do you want to use a external disk to store datadirectories of ownCloud, Samba, ... on it?"
   exit_status=$?
   case $exit_status in
      0)
         . data_to_external_disk.sh
         if $DATA_TO_EXTERNAL_DISK;then
            echo "DATA_TO_EXTERNAL_DISK=true" > /var/lib/apis/conf
            echo "EXTERNAL_DATA_DIR=\"$EXTERNAL_DATA_DIR\"" >> /var/lib/apis/conf
         else
            echo "DATA_TO_EXTERNAL_DISK=false" > /var/lib/apis/conf
            echo "EXTERNAL_DATA_DIR=''" >> /var/lib/apis/conf
         fi
         ;;
      1)
         echo "DATA_TO_EXTERNAL_DISK=false" > /var/lib/apis/conf
         echo "EXTERNAL_DATA_DIR=''" >> /var/lib/apis/conf
         ;;
      *)
         exit
         ;;
   esac
   # If you add a new component like foo_installer.sh, add a variable here.
   # E.g: echo "FOO_INSTALLED=false" >> /var/lib/apis/conf
   echo "OWNCLOUD_INSTALLED=false" >> /var/lib/apis/conf
   echo "SAMBA_INSTALLED=false" >> /var/lib/apis/conf
   echo "BTSYNC_INSTALLED=false" >> /var/lib/apis/conf
   echo "NFS_INSTALLED=false" >> /var/lib/apis/conf
   echo "NGINX_INSTALLED=false" >> /var/lib/apis/conf
   echo "NGINX_REQUIRED=''" >> /var/lib/apis/conf
   echo "AMPACHE_INSTALLED=false" >> /var/lib/apis/conf
   echo "SEAFILE_INSTALLED=false" >> /var/lib/apis/conf
   echo "PYLOAD_INSTALLED=false" >> /var/lib/apis/conf
fi

# Updater: check if '/var/lib/apis/conf' contains all required variables
# If you add a new component like foo_installer.sh, add a new variable (FOO_INSTALLED) to REQIURED_VARS
if [ "$1" == "update" ]; then
   REQIURED_VARS="DATA_TO_EXTERNAL_DISK OWNCLOUD_INSTALLED SAMBA_INSTALLED BTSYNC_INSTALLED NFS_INSTALLED NGINX_INSTALLED AMPACHE_INSTALLED SEAFILE_INSTALLED PYLOAD_INSTALLED"
   for var in $REQIURED_VARS; do
      grep -q $var /var/lib/apis/conf || echo "$var=false" >> /var/lib/apis/conf
   done
   exit
fi

main
