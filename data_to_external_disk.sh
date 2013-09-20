function edit_fstab(){
   echo $"Editing /etc/fstab"
   grep -q APIS /etc/fstab && return 1
cat >> /etc/fstab << EOF

# Created by APIS - The Awesome Pi Installation Script
/dev/$1  /mnt/data/            ext4    defaults,noexec,noatime  0       2
EOF
}

function lsblk_parser(){
   lsblk -o KNAME,$1 /dev/$2 | grep -E "$2 " | sed s@$2@@ | tr -d "[:blank:]"
}

function get_datadir_manually(){
   while true;do
      EXTERNAL_DATA_DIR="$(user_input $"Enter path" $"Enter the path to the datadirectory of your choice:")"
      if [ $? -ne 0 ]; then
         data_to_external_disk
         return
      fi
      test -d "$EXTERNAL_DATA_DIR" && break
      if ! yes_no $"ERROR" $"Directory doesn't exist! Try again?"; then
         data_to_external_disk
         return
      fi
   done
}

function external_storage_setup(){
   print_message $"Connect device" $"If you haven't connected the USB device yet, connect it now!"

   disks=($(lsblk -o KNAME | grep -v KNAME))
   length=${#disks[*]}
   items=()
   for ((i=1; i<=$length; i++)); do
      number="$i"
      device_info="$(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL,RM | sed -n $[$i+1]p)"
      items+=("$number" "$device_info")
   done

   part_choice=""
   while true; do
      part_choice=$(whiptail --title $"Available devices and partitions" --menu $"The list shows following information of connected devices:\nNUMBER, NAME, SIZE, TYPE, MOUNTPOINT, MODLENAME, REMOVABLE\nIf you select an entire disk, all partitions will be deleted and one single partition with maximum size will be created. Choose a partition or a disk (1-$length):" 30 90 15 "${items[@]}" 3>&1 1>&2 2>&3)
      if [ $? -ne 0 ]; then
         data_to_external_disk
         return
      fi
      [ "$part_choice" != "" ] && break
   done

   yes_no $"WARNING" $"Formating the disk/partition will erase all data stored on the it! The disk will be formated now. Are you sure you want to continue?"
   if [ $? -ne 0 ]; then
      data_to_external_disk
      return
   fi

   selected_disk="${disks[$part_choice-1]}"
   if [ "$(lsblk_parser "TYPE" "$selected_disk")" == "disk" ]; then
      # check if still mounted. if yes, umount
      if grep -q "$selected_disk" /proc/mounts; then
         echo $"The device is still mounted, trying umount..."
         umount $(grep $selected_disk /proc/mounts | cut -d ' ' -f 1 | tr "\n" " ")
         if [ $? -ne 0 ]; then
            error_msg $"Datadirectories will remain on the SD Card"
            return 1
         fi
         echo $"Unmmounted successfully."
      fi
      # formating und mounting
      (echo o; echo n; echo p; echo 1; echo; echo; echo w ) | fdisk /dev/$selected_disk &&
      mkfs.ext4 /dev/${selected_disk}1
      mkdir -p /mnt/data/
      edit_fstab ${selected_disk}1
      mount /dev/${selected_disk}1 /mnt/data/

   elif [ "$(lsblk_parser "TYPE" "$selected_disk")" == "part" ]; then
      # check if still mounted. if yes, umount
      if grep -q "$selected_disk" /proc/mounts; then
         echo $"The device is still mounted, trying umount..."
         umount  /dev/$selected_disk
         if [ $? -ne 0 ]; then
            error_msg $"Datadirectories will remain on the SD Card"
            return 1
         fi
         echo $"Unmmounted successfully."
      fi
      # formating und mounting
      mkfs.ext4 /dev/$selected_disk
      mkdir -p /mnt/data/
      edit_fstab "$selected_disk"
      mount /dev/$selected_disk /mnt/data/
   fi

   EXTERNAL_DATA_DIR='/mnt/data'
   hint_msg $"Setup complete. The device is mounted on '/mnt/data'"
   return 0
}

function data_to_external_disk(){
   choice=""
   choice=$(whiptail --ok-button $"Select" --cancel-button $"Exit" --title $"Storage setup" --menu $"IMPOTRANT: If you choose the first option, this script will erase and format the disk/partition. Choose one of the following three options:" 30 90 15 \
      1 $"Move datadirectories to external Storage" \
      2 $"Enter the datadirectory manually" \
      3 $"Leave the datadirectory on the SD Card" 3>&1 1>&2 2>&3)

   case $choice in 
      1)
         external_storage_setup
         ;;
      2)
         get_datadir_manually
         ;;
      3)
         DATA_TO_EXTERNAL_DISK=false
         ;;
      *)
         return 1
         ;;
   esac
   return 0
}

data_to_external_disk
