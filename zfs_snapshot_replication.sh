#!/bin/bash

# Source/Destination variables
source_pool="<zfs_source_pool>"
source_dataset="<zfs_source_dataset>"
destination_pool="<zfs_destination_pool>"
destination_dataset="<zfs_destination_dataset>"

# ZFS snapshot settings
snapshots="no"
snapshot_hours="0"
snapshot_days="7"
snapshot_weeks="4"
snapshot_months="3"
snapshot_years="0"

# Derived variables
source_path=$source_pool/$source_dataset
destination_dataset_path=$destination_pool/$destination_dataset
destination_path=$destination_dataset_path/${source_pool}_${source_dataset}
sanoid_config_dir=/mnt/user/system/sanoid
sanoid_config_complete_path=$sanoid_config_dir/${source_pool}_${source_dataset}


# Function to crete snapshot config
create_snapshot_config()
{
  # check if the configuration directory exists, if not create it
  if [ ! -d $sanoid_config_complete_path ]; then
    echo "Snaphsot config directory does not exist, making it"
    mkdir -p $sanoid_config_complete_path
  fi
  
  # check if the sanoid.defaults.conf file exists in the configuration directory, if not copy it from the default location
  if [ ! -f $sanoid_config_complete_path/sanoid.defaults.conf ]; then
    echo "Copying default config"
    cp /etc/sanoid/sanoid.defaults.conf $sanoid_config_complete_path/sanoid.defaults.conf
  fi
  
  # check if a configuration file has already been created from a previous run, if so exit the function
  if [ -f $sanoid_config_complete_path/sanoid.conf ]; then
    echo "Snapshot config file already exists"
    return
  fi

  # Create config file
  echo "Creating snapshot config file"
  config_file=$sanoid_config_complete_path/sanoid.conf
  echo "[${source_path}]" > $config_file
  echo "use_template = production" >> $config_file
  echo "recursive = yes" >> $config_file
  echo "" >> $config_file
  echo "[template_production]" >> $config_file
  echo "hourly = ${snapshot_hours}" >> $config_file
  echo "daily = ${snapshot_days}" >> $config_file
  echo "weekly = ${snapshot_weeks}" >> $config_file
  echo "monthly = ${snapshot_months}" >> $config_file
  echo "yearly = ${snapshot_years}" >> $config_file
  echo "autosnap = yes" >> $config_file
  echo "autoprune = yes" >> $config_file
}


# Function to create snapshots
create_snapshots()
{
  # Create the snapshots of the source directory using Sanoid if required
  echo "Creating snapshots"
  /usr/local/sbin/sanoid --configdir=$sanoid_config_complete_path --take-snapshots

  # Check the exit status of the sanoid command 
  if [ $? -eq 0 ]; then
    echo "Snapshot creation successful"
  else
    echo "Snapshot creation failed"
  fi
}


# Function to prune snapshots
prune_snapshots()
{
  echo "Pruning snapshots"
  /usr/local/sbin/sanoid --configdir=$sanoid_config_complete_path --prune-snapshots
  
  # Check the exit status of the sanoid command 
  if [ $? -eq 0 ]; then
    echo "Snapshot pruning successful"
  else
    echo "Snapshot pruning failed"
  fi
}

# Perform snapshot functions
zfs_snapshots()
{
  # Exit if autosnapshots not enabled
  if [ $snapshots != "yes" ]; then
    echo "Snapshots disabled, skipping"
    return
  fi
  
  create_snapshot_config
  create_snapshots
  prune_snapshots
}

# This function does the zfs replication
zfs_replication()
{
  # check if the parent destination ZFS dataset exists locally. If not, create it.
  if ! zfs list -o name -H $destination_dataset_path &>/dev/null; then
    echo "Destination ${destination_dataset_path} does not exist, creating it"
    zfs create $destination_dataset_path
    if [ $? -ne 0 ]; then
      echo "Failed to check or create local ZFS dataset: ${destination_dataset_pool}"
      return
    fi
  fi

  # Use syncoid to replicate snapshot to the destination dataset
  echo "Starting ZFS replication"
  /usr/local/sbin/syncoid -r --force-delete --delete-target-snapshots $source_path $destination_path
  
  if [ $? -eq 0 ]; then
    echo "ZFS replication was successful from source: ${source_path} to destination: ${destination_path}"
  else
    echo "ZFS replication failed from source: ${source_path} to destination: ${destination_path}"
    return
  fi
}

# Run the above functions
zfs_snapshots
zfs_replication
