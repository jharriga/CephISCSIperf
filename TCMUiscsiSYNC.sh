#!/bin/bash
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# BASH script to automate RBD and ISCSI comparision testing
# Uses fio to execute tests
# Assumes the colloing Ceph devices are preconfigured
# Pools: iscsiTest and rbdTest
# Devices: sixty 100GB LUNs in each pool
# Image Naming: $client-isciTest-N (1-20), rbdTest-N (1-60)
# RBD Devices are pre-mapped on all clients
#  > 8  rbdTest rbdTest-1  -    /dev/rbd8
#    <... SNIP ...>
#  > 67 rbdTest rbdTest-60 -    /dev/rbd67 
# iSCSI LUNs are logged into by their clients and presented
#   as device mapper devices /dev/mapper/mpath
#
# Writes results files in this dir structure:
#    RESULTS/
#      /<timestamp>_$testType/$operation_$iodepth/
#         $pool_$client_$blocksize
#
# Be sure that pbench-agent-internal is installed on all systems
# and that 'pbench-register-tool-set' has been run on all clients
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##############################################
# GLOBAL VARS
# - configure pbench_fio run settings
#----------------------------------------------
#iscsidev_list="/dev/mapper/mpathao /dev/mapper/mpathap /dev/mapper/mpathaq /dev/mapper/mpathar /dev/mapper/mpathas /dev/mapper/mpathat /dev/mapper/mpathau /dev/mapper/mpathav /dev/mapper/mpathaw /dev/mapper/mpathax /dev/mapper/mpathay /dev/mapper/mpathaz /dev/mapper/mpathba /dev/mapper/mpathbb /dev/mapper/mpathbc /dev/mapper/mpathbd /dev/mapper/mpathbe /dev/mapper/mpathbf /dev/mapper/mpathbg /dev/mapper/mpathbh"
#iscsidev_list="/dev/dm-3 /dev/dm-4 /dev/dm-5 /dev/dm-6 /dev/dm-7 /dev/dm-8 /dev/dm-9 /dev/dm-10 /dev/dm-11 /dev/dm-12 /dev/dm-13 /dev/dm-14 /dev/dm-15 /dev/dm-16 /dev/dm-17 /dev/dm-18 /dev/dm-19 /dev/dm-20 /dev/dm-21 /dev/dm-22"
# Dev list as of Dec 20th
iscsidev_list="/dev/mapper/mpatha /dev/mapper/mpathb /dev/mapper/mpathc /dev/mapper/mpathd /dev/mapper/mpathe /dev/mapper/mpathf /dev/mapper/mpathg /dev/mapper/mpathh /dev/mapper/mpathi /dev/mapper/mpathj /dev/mapper/mpathk /dev/mapper/mpathl /dev/mapper/mpathm /dev/mapper/mpathn /dev/mapper/mpatho /dev/mapper/mpathp /dev/mapper/mpathq /dev/mapper/mpathr /dev/mapper/mpaths /dev/mapper/mpatht"

devcnt=10                # number of devices per client

testType="rbdblock"
basename_blk="/dev/rbd"
rbdPool_startindex=8           # first mapped: /dev/rbd8
rbdPool_endindex=67            # last mapped: /dev/rbd67

# Hosts and clients
cephServer="gprfc092"
#pdsh_clients="gprfc[093-095]"
pdsh_clients="gprfc[094-095]"
#client_list="gprfc093 gprfc094 gprfc095"
client_list="gprfc094 gprfc095"

# FIO - for loop conditions (in order)
pool_list="iscsiTest"
#pool_list="rbdTest"
operation_list="read randwrite randread"
#operation_list="read"
#ioengine="libaio"
#---------------------------------------
# SYNC test options:  sync (default) 
ioengine="sync"
iodepth_list="1"
#---------------------------------------
#blocksize_list="4k 64k 4096k"
blocksize_list="4k 64k 1024k"
#iodepth_list="8 32"
#devcnt_list="1 5 20"            # number devices accessed/client

# FIO - GLOBAL section
runtime=300
ramp=15
devsize=80g

# Paths & filenames
fio_basename="/tmp/fiojob."   # Unique jobfile per client
fio_tmp="/tmp/jobfile.fio"    # remote fio jobfile name
fioplot_tmp="/tmp/FIOplot"    # dir to hold fio plot logfiles
dir="./RESULTS"
clientfile="/tmp/clients"
#
#----------------------------------------------
# END GLOBAL VARS
##############################################


##############################################
# FUNCTIONS
#----------------------------------------------
# writeFIOglobal - creates FIO jobfile global section
function writeFIOglobal {
# Create FIO jobfile - GLOBAL section
  local fname=$1              # /tmp/jobfile.gprfc094
  local pname=$2              # e.g. rbdTest

    if [ $ioengine == "rbd" ]; then
        io_str=$(printf "rbd\nclientname=admin\npool=${pname}\n")
    else
        io_str=${ioengine}
    fi

    if [ $oper == "read" ]; then
        directio_setting=0
    else
        directio_setting=1
    fi

    cat <<EOF1 > ${fname}
[global]
group_reporting=1
time_based=1
runtime=${runtime}
clocksource=clock_gettime
ramp_time=${ramp}
ioengine=${io_str}
direct=${directio_setting}
invalidate=1
fsync_on_close=1
bs=${bs}
iodepth=${iod}
rw=${oper}
rwmixread=80
size=${devsize}
per_job_logs=0
write_bw_log=${fioplot_tmp}/${cl}-results
write_iops_log=${fioplot_tmp}/${cl}-results
write_lat_log=${fioplot_tmp}/${cl}-results
EOF1

}   # END writeFIOglobal

# appendFIOjob - appends FIO job sections per device
# Requires three passed params - jobnumber and devicename
# NOTE: opening empty line for FIO jobfile formatting
function appendFIOjob {
    local fname=$1
    local jobstring=$2
    local devstring=$3

    if [ $ioengine == "rbd" ]; then
        identifier="rbdname"
    else
        identifier="filename"
    fi

    cat <<EOF2 >> ${fname}

[${jobstring}]
${identifier}=${devstring}
EOF2

}   # END appendFIOjob

#----------------------------------------------
# END FUNCTIONS
##############################################

##############################################
# SCRIPT
#----------------------------------------------
echo "Start: " `date`

# populate clientfile
rm -f ${clientfile}
touch ${clientfile}
declare -i numclients=0
for cl in $client_list; do
    numclients=$(( numclients+1 ))
    echo "${cl}" >> ${clientfile}
done

# Name and create empty results directory
rundate=`date +'%Y%m%d-%H%M'`
testname="${rundate}_${testType}_DEVCNT${devcnt}"
rundir="${dir}/${testname}"
mkdir "${rundir}"

# Outer FOR Loop
for pool in $pool_list ; do

  declare -a devarray=()

  # populate device array - depending on pool-type
  if [ $pool == "rbdTest" ]; then
      # set device offset for this pool
      start=$rbdPool_startindex
      end=$rbdPool_endindex
      pool_devcnt=$(( $end-$start+1 ))

      # populate the entire device list for this Pool
      for ((i=$start; i<=$end; i++)); do
        devarray=("${devarray[@]}" "${basename_blk}${i}")
      done
  else     # pool = iscsiTest
      # populate the entire device list for this Pool
      for iscsidev in $iscsidev_list; do
          devarray=("${devarray[@]}" "${iscsidev}")
      done
  fi

  #echo "Number of elements in ${pool}: ${#devarray[@]}"
  #echo "${devarray[@]}"
  #exit

  for oper in $operation_list ; do
    for iod in $iodepth_list; do
      # Name and create the 'oper_iod' results directory
      dirname="${oper}_IOD${iod}"
      resultsdir="${rundir}/${dirname}"
      if [ ! -d "$resultsdir" ]; then
        mkdir "${resultsdir}"
      fi
      for bs in $blocksize_list; do
        #-------------------------------
        # loop over the clientlist
        # create the per client fio jobfile
        for cl in $client_list; do
          # Create FIO jobfile to be used for this run
          # - GLOBAL section
          fiofile="${fio_basename}${cl}"
          writeFIOglobal ${fiofile} ${pool}

          # Append to FIO jobfile - JOBS section
          declare -i cnt=0
          declare -i x=0
          if [ $pool == "rbdTest" ]; then
              stride=$numclients
          else     # pool is iscsiTest
              stride=1
          fi
          while [ $cnt -lt $devcnt ]; do
            cnt=$(( $cnt+1 ))
            dev=${devarray[x]}
            job="${cl}-${pool}-${ioengine}-${cnt}"
            # pass the fio, job and device names
            appendFIOjob ${fiofile} ${job} ${dev}
            x=$(( $x+$stride ))
          done
          #cat ${fiofile}
          #echo ${resultsdir}
          #exit
        done
        # FIO jobfiles written
        #----------------------------------

        #-----------------------------------
        # Prepare for fio run
        # Drop caches on clients
        pdsh -S -w $pdsh_clients "sync ; \
          echo 3 > /proc/sys/vm/drop_caches" &> /dev/null
        sleep 5
        echo " ---> ${testname}" 

        # Start remote ceph watch
        ssh ${cephServer} "ceph -w > /tmp/ceph-watch &" &> /dev/null

        #####################################
        # run FIO manually on clients
        #
        # copy the fio jobfile to the clients
        # loop over the clientlist
        for this_client in $client_list; do
            this_file="${fio_basename}${this_client}"
            scp -q ${this_file} "${this_client}:${fio_tmp}"
        done

        # now invoke FIO run on the clients
        pdsh -S -w $pdsh_clients "rm -rf ${fioplot_tmp}"
        pdsh -S -w $pdsh_clients "mkdir ${fioplot_tmp}"
        pdsh -S -w $pdsh_clients "cat ${fio_tmp} > /tmp/fioHOLD.log"
        pdsh -S -w $pdsh_clients "fio ${fio_tmp} &>> /tmp/fioHOLD.log"

        # FIO done - stop cephwatch process
        ssh ${cephServer} "pkill -f \"ceph -w\" "

        # copy back FIO results and store the results
        for this_client in $client_list; do
            resfile="${pool}_${this_client}_BS${bs}"
            this_result="${resultsdir}/${resfile}.results"
            scp -q "${this_client}:/tmp/fioHOLD.log" ${this_result}
            scp -q -r "${this_client}:${fioplot_tmp}" ${resultsdir}
        done

        # copy back cephwatch results
        cephwatch="${resultsdir}/ceph-watch.${pool}_BS${bs}"
        scp -q ${cephServer}:/tmp/ceph-watch ${cephwatch}

        #----------------------------------
        # pbench-fio done - Cleanup and collect results
        # Move pbench-agent results dir and logfile to resultsdir
#        pbenchdir=`ls -rtd /var/lib/pbench-agent/fio_*/ |tail -1`
#        mv ${pbenchdir} ${resultsdir}
#        mv ${testname}.log ${resultsdir}
#        echo "pbenchdir: ${pbenchdir}"    # DEBUG
        echo "resultsdir: ${resultsdir}"  # DEBUG
        echo "cephwatch: ${cephwatch}"    # DEBUG
        #----------------------------------

      done  # end FOR $bs
     done   # end FOR $iod
    done    # end FOR $oper

    # Completion timestamp
    echo -e "---------------\n"
    echo "Completed pool ${pool}: " `date`
    echo "Results are at: ${rundir}"
    echo -e "+++++++++++++++++++++++++++++++++++++++++\n"

done    # end FOR $pool

# Completion timestamp
echo "Completed all tests: " `date`
echo " *** DONE ***"

#
#----------------------------------------------
# END SCRIPT
##############################################
