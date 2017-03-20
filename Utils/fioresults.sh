#!/bin/bash
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# BASH script to echo FIO results from run directories 
# expects one argument, pathname to results directory
#

path=${1%/}
blksz_list="4k 64k 1024k"

##############################################
# SCRIPT
#----------------------------------------------

if [ ! -d "$path" ]; then
  echo "directory does not exist - exiting"
  exit
fi

for bs in $blksz_list; do
  # start with null output strings
  bw1=""
  bw2=""
  lat=""

  this_glob="${path}/*_BS${bs}.results"
  filecnt="$( ls $this_glob | wc -l )"

  declare -i loopcnt=0
  for fname in $this_glob; do
    
    if (( $loopcnt == 0 )); then
      iod="$( awk 'BEGIN { FS="=" } /^iodepth=/ {print $2}' ${fname} )"
      ioeng="$( awk 'BEGIN { FS="=" } /^ioengine=/ {print $2}' ${fname} )"
      oper="$( awk 'BEGIN { FS="=" } /^rw=/ {print $2}' ${fname} )"
      echo "--------------------------------------------------------"
      echo "FIO settings: bs=$bs rw=$oper iodepth=$iod ioengine=$ioeng"
      echo "  BS${bs} -> Found ${filecnt} results files"
      echo "-------------"
    fi
    loopcnt=$((loopcnt+1))
    
    grepstr1=""
    grepstr2=""
    case $oper in 
      read)
        grepstr1="READ:"
        ;;
      write)
        grepstr1="WRITE:"
        ;;
      randread)
        grepstr1="READ:"
        ;;
      randwrite)
        grepstr1="WRITE:"
        ;;
      randrw)
        grepstr1="READ:"
        grepstr2="WRITE:"
        ;;
    esac

#    tmpbw1="$( grep ${grepstr1} ${fname} )"
    bw1="$( awk 'BEGIN { FS="," } /aggrb=/ {print $2}' ${fname} )"
    if [ "$grepstr2" != "" ]; then
#      tmpbw2="$( grep ${grepstr2} ${fname} )"
      bw2="$( awk 'BEGIN { FS="," } /aggrb=/ {print $2}' ${fname} )"
    fi
    tmplat="$( grep -h "[^a-z]lat ([m-u]sec):" ${fname} )"
    unit="$( echo ${tmplat} | awk 'BEGIN { FS=":" } /lat/ {print $1}' )"
    lat="$( echo ${tmplat} | awk 'BEGIN { FS="," } /avg=/ {print $3}' )"
    stdev="$( echo ${tmplat} | awk 'BEGIN { FS="," } /stdev=/ {print $4}' )"

    # echo the results line
    echo "${fname##*/}:"
    echo -e "  ${bw1}   ${unit}${lat} ${stdev}\n" 
  done

done
echo "----------------------------"

# END

