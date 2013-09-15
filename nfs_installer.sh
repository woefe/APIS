function install_nfs(){
   yes_no $"Install NFS" $"WARNING: This installer may overwrite any existing NFS related configuration files. Ignore this warning if you haven't installed NFS yet.\nDo you really want to install the NFS server?" || return 1
   apt-get install -qq nfs-kernel-server portmap

   EXPORTPATH=/srv/nfs
   $DATA_TO_EXTERNAL_DISK && EXPORTPATH=/mnt/data/nfs
   EXPORTPATH=$(user_input $"Choose directory" $"Enter the path to the directory that you want to share via NFS. Hit 'return' to use the default path." "$EXPORTPATH") || return 1
   if [ ! -d $EXPORTPATH ]; then
      yes_no $"Directory doesn't exist" $"'$EXPORTPATH' doesn't exist. Do you want to create it?" || return 1
      mkdir -p $EXPORTPATH
   fi

   i=0
   while true; do
      CLIENT[$i]=$(user_input $"Add client $[$i+1]" $"Whom do you want to grant access on this shared directory? Enter only one IP address, hostname or subnet.")
      exitstatus=$?
      if [ -z ${CLIENT[*]} ]; then
         error_msg $"No input. Enter a IP address (e.g. '192.168.0.5'), a hostname (e.g. 'ubuntu-desktop' or whatever your computer's name is) or a subnet (e.g. 192.168.0.0/24)."
         continue
      elif [ -z ${CLIENT[$i]} ];then
         yes_no $"Add more clients" $"Do you want to add more clients to '$EXPORTPATH'?" || break
      elif [ $exitstatus -ne 0 ]; then
         yes_no $"Add more clients" $"Do you want to add more clients to '$EXPORTPATH'?" || break
      fi

      if ! echo ${CLIENT[$i]} | grep -q / ; then
         ping -c 2 ${CLIENT[$i]} > /dev/null || yes_no $"WARNING" $"'${CLIENT[$i]}' is currently not available. Add '${CLIENT[$i]}' anyways?" || continue
      fi

      while true; do
         PERMISSIONS[$i]=$(whiptail --title $"Set permissions" --radiolist $"Select permissions for '${CLIENT[$i]}' on '$EXPORTPATH'." 30 90 20 \
            rw $"'${CLIENT[$i]}' can read and write files on '$EXPORTPATH'" 1 \
            ro $"'${CLIENT[$i]}' can read files on '$EXPORTPATH'" 0 3>&1 1>&2 2>&3 )
         if [ $? -ne 0 ]; then
            print_message $"Nothing selected" $"You have to select either 'read and write' or 'read only'!"
         else
            break
         fi
      done
      yes_no $"Add more clients" $"Do you want to add more clients to '$EXPORTPATH'?" || break
      i=$[$i+1]
   done
   hint_msg $"You can add more shares later by selecting 'nfs_setup' in the main menu."

   cat > /etc/exports << EOF 
# /etc/exports: the access control list for filesystems which may be exported
#               to NFS clients.  See exports(5).
#
# Example for NFSv2 and NFSv3:
# /srv/homes       hostname1(rw,sync,no_subtree_check) hostname2(ro,sync,no_subtree_check)
#
# Example for NFSv4:
# /srv/nfs4        gss/krb5i(rw,sync,fsid=0,crossmnt,no_subtree_check)
# /srv/nfs4/homes  gss/krb5i(rw,sync,no_subtree_check)
#
EOF
   echo -e "$EXPORTPATH\t$(for ((i=0; i<${#CLIENT[*]}; i++)); do [ -n ${CLIENT[$i]} ] && echo -n " ${CLIENT[$i]}(${PERMISSIONS[$i]},async)"; done)" >> /etc/exports

   update-rc.d rpcbind enable
   service rpcbind start
   service nfs-kernel-server start
   service nfs-kernel-server status
   if [ $? -ne 0 ] ; then
      return 1
   else
      hint_msg $"NFS server is now installed. Clients can now mount NFS shares. Command to mount NFS shares on clients:\nsudo mount IPADDRESS_OF_YOUR_NFS_SERVER:/path/to/shared/directory /path/to/dir"
      return
   fi
}

function uninstall_nfs(){
   yes_no $"Uninstall NFS" $"Do you really want to uninstall NFS server? The content of your shared directories won't be deleted." || return 1
   service nfs-kernel-server stop
   apt-get purge -qq nfs-kernel-server
}

function add_nfs_shares(){
   EXPORTPATH=/srv/nfs
   $DATA_TO_EXTERNAL_DISK && EXPORTPATH=/mnt/data/nfs
   EXPORTPATH=$(user_input $"Share a directory" $"Enter the path to the directory that you want to share via NFS. Hit 'return' to use the default path." "$EXPORTPATH") || return 1
   if [ ! -d $EXPORTPATH ]; then
      yes_no $"Directory doesn't exist" $"'$EXPORTPATH' doesn't exist. Do you want to create it?" || return 1
      mkdir -p $EXPORTPATH
   elif grep -q "$EXPORTPATH[[:blank:]]" /etc/exports; then
      error_msg $"This directory is already shared via NFS."
      return 1
   fi

   i=0
   while true; do
      CLIENT[$i]=$(user_input $"Add client $[$i+1]" $"Whom do you want to grant access on this shared directory? Enter only one IP address, hostname or subnet.")
      exitstatus=$?
      if [ -z "${CLIENT[*]}" ]; then
         error_msg $"No input. Enter a IP address (e.g. '192.168.0.5'), a hostname (e.g. 'ubuntu-desktop' or whatever your computer's name is) or a subnet (e.g. 192.168.0.0/24)."
         continue
      elif [ -z ${CLIENT[$i]} ];then
         yes_no $"Add more clients" $"Do you want to add more clients to '$EXPORTPATH'? If you select 'no', the share will not be created!" || return 1
      elif [ $exitstatus -ne 0 ]; then
         yes_no $"Add more clients" $"Do you want to add more clients to '$EXPORTPATH'? If you select 'no', the share will not be created!" || return 1
      fi

      if ! echo ${CLIENT[$i]} | grep -q / ; then
         ping -c 2 ${CLIENT[$i]} > /dev/null || yes_no $"WARNING" $"'${CLIENT[$i]}' is currently not available. Add '${CLIENT[$i]}' anyways?" || continue
      fi

      while true; do
         PERMISSIONS[$i]=$(whiptail --title $"Set permissions" --radiolist $"Select permissions for '${CLIENT[$i]}' on '$EXPORTPATH'." 30 90 20 \
            rw $"'${CLIENT[$i]}' can read and write files on '$EXPORTPATH'" 1 \
            ro $"'${CLIENT[$i]}' can read files on '$EXPORTPATH'" 0 3>&1 1>&2 2>&3 )
         if [ $? -ne 0 ]; then
            print_message $"Nothing selected" $"You have to select either 'read and write' or 'read only'!"
         else
            break
         fi
      done
      yes_no $"Add more clients" $"Do you want to add more clients to '$EXPORTPATH'?" || break
      i=$[$i+1]
   done

   echo -e "$EXPORTPATH\t$(for ((i=0; i<${#CLIENT[*]}; i++)); do [ -n ${CLIENT[$i]} ] && echo -n " ${CLIENT[$i]}(${PERMISSIONS[$i]},async)"; done)" >> /etc/exports
   exit_message
   return
}

function remove_nfs_shares(){
   AVAILABLE_SHARES=($(grep -v '#' /etc/exports | tr '[:blank:]' ';' | cut -d\; -f1))
   if [ -z $AVAILABLE_SHARES ]; then
      error_msg $"No NFS exports available."
      return 1
   fi
   TAG_ITEM=$(for ((i=0; i<${#AVAILABLE_SHARES[*]}; i++)); do \
      echo -n "${AVAILABLE_SHARES[$i]} $i " ; \
   done)
   SELECTED_SHARE=$(whiptail --title $"Remove NFS shares" --noitem --menu $"Select the NFS share which you want to delete." 30 90 20 $TAG_ITEM 3>&1 1>&2 2>&3 | tr -d \")
   [ -z $SELECTED_SHARE ] && return 1
   yes_no $"Remove NFS shares" $"Do you really want to delete '$SELECTED_SHARE'?" || return
   linenumber=$(grep -ne "$SELECTED_SHARE[[:blank:]]" /etc/exports | cut -d: -f1)
   sed -i $linenumber\d /etc/exports
   exit_message
   return
}

function add_clients_to_nfs_shares(){
   AVAILABLE_SHARES=($(grep -v '#' /etc/exports | tr '[:blank:]' ';' | cut -d\; -f1))
   if [ -z $AVAILABLE_SHARES ]; then
      error_msg $"No NFS exports available."
      return 1
   fi
   TAG_ITEM=$(for ((i=0; i<${#AVAILABLE_SHARES[*]}; i++)); do \
      echo -n " ${AVAILABLE_SHARES[$i]} $i " ;\
   done)

   SELECTED_SHARE=$(whiptail --title $"Add clients to your NFS shares" --noitem --menu $"Select the NFS share to which you want to add more clients." 30 90 20 $TAG_ITEM 3>&1 1>&2 2>&3 | tr -d \")
   [ -z $SELECTED_SHARE ] && return 1
   while true; do
      CLIENT=$(user_input $"Add more clients" $"Whom do you want to grant access on '$SELECTED_SHARE'? Enter only one IP address, hostname or subnet.")
      exitstatus=$?
      if [ $exitstatus -ne 0 ]; then
         yes_no $"Add more clients" $"Do you want to add more clients to '$SELECTED_SHARE'?" || return 1
         continue
      elif [ -z $CLIENT ];then
         error_msg $"No input. Enter a IP address (e.g. '192.168.0.5'), a hostname (e.g. 'ubuntu-desktop' or whatever your computer's name is) or a subnet (e.g. 192.168.0.0/24)."
         continue
      fi

      if ! echo $CLIENT | grep -q / ; then
         ping -c 2 $CLIENT > /dev/null || yes_no $"WARNING" $"'$CLIENT' is currently not available. Add '$CLIENT' anyways?" || continue
      fi

      while true; do
         PERMISSIONS=$(whiptail --title $"Set permissions" --radiolist $"Select permissions for '$CLIENT' on '$SELECTED_SHARE'." 30 90 20 \
            rw $"'$CLIENT' can read and write files on '$SELECTED_SHARE'" 1 \
            ro $"'$CLIENT' can read files on '$SELECTED_SHARE'" 0 3>&1 1>&2 2>&3 )
         if [ $? -ne 0 ]; then
            print_message $"Nothing selected" $"You have to select either 'read and write' or 'read only'!"
         else
            break
         fi
      done

      linenumber=$(grep -ne "$SELECTED_SHARE[[:blank:]]" /etc/exports | cut -d: -f1)
      sed -i $linenumber\s+$+\ $CLIENT\($PERMISSIONS,async\)+ /etc/exports
      yes_no $"Add more clients" $"Do you want to add more clients to '$SELECTED_SHARE'?" || break
   done
   exit_message
   return
}

function remove_clients_from_nfs_shares(){
   AVAILABLE_SHARES=($(grep -v '#' /etc/exports | tr '[:blank:]' ';' | cut -d\; -f1))
   if [ -z $AVAILABLE_SHARES ]; then
      error_msg $"No NFS exports available."
      return 1
   fi
   TAG_ITEM=$(for ((i=0; i<${#AVAILABLE_SHARES[*]}; i++)); do \
      echo -n "${AVAILABLE_SHARES[$i]} $i " ;\
   done)
   SELECTED_SHARE=$(whiptail --title $"Remove clients from NFS shares" --noitem --menu $"Select the NFS share from which you want to delete clients." 30 90 20 $TAG_ITEM 3>&1 1>&2 2>&3 | tr -d \")
   [ -z $SELECTED_SHARE ] && return 1
   while true; do
      INSTALLED_CLIENTS=($(grep $SELECTED_SHARE[[:blank:]] /etc/exports | tr '[:blank:]' ';' | cut -d\; -f2- --output-delimiter=' '))
      TAG_ITEM=$(for ((i=0; i<${#INSTALLED_CLIENTS[*]}; i++)); do \
         echo -n "${INSTALLED_CLIENTS[$i]} \"$i\" " ;\
      done)

      SELECTED_CLIENT=$(whiptail --title $"Remove clients from NFS shares" --noitem --menu $"Select the client which you want to delete from '$SELECTED_SHARE'.\n   Used Syntax: 'clientname(permissions,options)'" 30 90 20 $TAG_ITEM 3>&1 1>&2 2>&3 )
      [ $? -ne 0 ] && break
      SELECTED_CLIENT=$(echo $SELECTED_CLIENT | tr -d \")
      yes_no $"Remove clients" $"Do you really want to delete '$SELECTED_CLIENT' from '$SELECTED_SHARE'?" || break
      linenumber=$(grep -ne "$SELECTED_SHARE[[:blank:]]" /etc/exports | cut -d: -f1)
      sed -i $linenumber\s@\ $SELECTED_CLIENT@@ /etc/exports
      yes_no $"Remove clients" $"Do you want to delete another client from '$SELECTED_SHARE'?" || break
   done
   exit_message
   return
}

function exit_message(){
   hint_msg $"If you changed the configuration, you have to restart NFS by issuing following command:\nsudo service nfs-kernel-server restart\nBefore you restart NFS make sure that all clients have unmounted the NFS exports."
}

case $1 in
   install)
      install_nfs
      ;;
   uninstall)
      uninstall_nfs
      ;;
   add-clients)
      add_clients_to_nfs_shares
      ;;
   add-shares)
      add_nfs_shares
      ;;
   delete-clients)
      remove_clients_from_nfs_shares
      ;;
   delete-shares)
      remove_nfs_shares
      ;;
esac

