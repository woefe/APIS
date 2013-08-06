function edit_fstab(){
   echo $"Editing /etc/fstab"
   echo "/dev/$1  /mnt/data/            ext4    defaults,noexec,noatime  0       2" >> /etc/fstab
}

function lsblk_parser(){
   lsblk -o KNAME,$1 /dev/$2 | grep -E "$2 " | sed s@$2@@ | tr -d "[:blank:]"
}

function data_to_external_disk(){
   clear
   echo "--------------"
   echo $"|  Storage   |"
   echo "--------------"
   echo -e $"You have got three options here:\n1. Move datadirectories to external Storage (HDD, USB; you can select a single partition or an entire disk)\n2. Enter the datadirectory manually\n3. Leave the datadirectory on the SD Card\n\nIMPOTRANT: If you choose the first option, this script will erase and format the Drive."
   read -p $"What's your choice? (1/2/3): " choice

   if [ "$choice" == "3" ]; then
      USE_EXTERNAL_SPACE=false

   elif [ "$choice" == "2" ]; then
      echo
      while true; do
         read -p $"Enter the path of your choice: " EXTERNAL_DATA_DIR
         test -d $EXTERNAL_DATA_DIR && break
         echo $"Path doesn't exist."
         read -p $"Try again? (y/n): " choice
         if [ "$choice" == $"n" ]; then
            data_to_external_disk && return
         fi
      done
      return

   elif [ "$choice" == "1" ]; then
      echo
      echo $"If you haven't connected the USB device yet, do it now."
      read -p $"Hit Enter to continue" tmpvar
      sleep 3
      echo $"Available devices and partitions:"
      echo
      disks=($(lsblk -o KNAME | grep -v KNAME))
      length=${#disks[*]}
      for ((i=0; i<$length; i++)); do
         echo -en "($[$i+1]) ${disks[$i]}:\t"
         echo -en "$(lsblk_parser "SIZE" ${disks[$i]})\t"
         echo -en "$(lsblk_parser "TYPE" ${disks[$i]})\t"
         mountpoint=$(lsblk_parser "MOUNTPOINT" "${disks[$i]}")
         if [ "$mountpoint" != "" ]; then
            echo -en $"mounted on '$mountpoint'\t"
         else
            echo -en "\t\t\t"
         fi
         ls -l /dev/disk/by-id/ | grep ${disks[$i]}$ | grep -Eo "usb[^ ]*|ata[^ ]*|memstick[^ ]*"
      done
      echo
      part_choice=""
      while true; do
         echo $"If you select an entire disk, all partitions will be deleted and one single partition with maximum size will be created"
         read -p $"Choose a partition or a disk (1-$length): " part_choice &&
         test "$part_choice" != "" &&
         test $part_choice -le $length &&
         break
         echo $"Your choice is invalid."
         echo
      done
      echo "         ----------------"
      echo $"         |    WARNING   |"
      echo "         ----------------"
      echo $"Formating the disk/partition will erase all data stored on the it."
      read -p $"The disk will be formated now. Are you sure you want to continue? (y/n): " tmpvar
      if [ "$tmpvar" != $"y" ]; then
         data_to_external_disk && return
      fi

      # Format Partition or delete partition table and then create a partition and format
      selected_disk="${disks[$part_choice-1]}"
      if [ "$(lsblk_parser "TYPE" "$selected_disk")" == "disk" ]; then
         # check if still mounted. if yes, umount
         if grep -q "$selected_disk" /proc/mounts; then
            echo $"The device is still mounted, trying umount..."
            umount $STANDARD_VERBOSE_FLAG $(grep $selected_disk /proc/mounts | cut -d ' ' -f 1 | tr "\n" " ") || (echo $"Datadirectories will remain on the SD Card" && return)
            echo $"Unmmounted successfully."
         fi
         # formating und mounting
         (echo o; echo n; echo p; echo 1; echo; echo; echo w ) | fdisk /dev/$selected_disk &&
         mkfs.ext4 $STANDARD_VERBOSE_FLAG /dev/$selected_disk\1
         mkdir -p $STANDARD_VERBOSE_FLAG /mnt/data/
         edit_fstab $selected_disk\1
         mount $STANDARD_VERBOSE_FLAG /dev/$selected_disk\1 /mnt/data/

      elif [ "$(lsblk_parser "TYPE" "$selected_disk")" == "part" ]; then
         # check if still mounted. if yes, umount
         if grep -q "$selected_disk" /proc/mounts; then
            echo $"The device is still mounted, trying umount..."
            umount $STANDARD_VERBOSE_FLAG /dev/$selected_disk || (echo $"Datadirectories will remain on the SD Card" && return)
            echo $"Unmmounted successfully."
         fi
         # formating und mounting
         mkfs.ext4 $STANDARD_VERBOSE_FLAG /dev/$selected_disk
         mkdir -p $STANDARD_VERBOSE_FLAG /mnt/data/
         edit_fstab "$selected_disk"
         mount $STANDARD_VERBOSE_FLAG /dev/$selected_disk /mnt/data/
      fi

   else
      data_to_external_disk && return
   fi
}
