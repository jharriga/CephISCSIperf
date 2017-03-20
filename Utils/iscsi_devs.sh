#!/bin/bash

devpath="/dev/"
iscsiglob="/dev/disk/by-path/ip-*"

declare -a devarray=()
for iscsidev in $iscsiglob; do
  tmp1=$( readlink $iscsidev )
  tmp2=$( basename $tmp1 )
  devarray=("${devarray[@]}" "${devpath}${tmp2}")
done

echo ${devarray[@]}

