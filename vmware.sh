#!/bin/bash
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# BASH script to automate RBD and ISCSI comparision testing
# Uses fio to execute tests
# Assumes the colloing Ceph devices are preconfigured
# Pools: iscsiTest and rbdTest
# Devices: sixty 100GB LUNs in each pool
# Image Naming: isciTest-N (1-60), rbdTest-N (1-60)
# Devices are pre-mapped on all clients
#  > 8  rbdTest rbdTest-1  -    /dev/rbd8
#    <... SNIP ...>
#  > 67 rbdTest rbdTest-60 -    /dev/rbd67 
#
# Be sure that pbench-agent-internal is installed on all systems
# and that 'pbench-register-tool-set' has been run on all clients
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

##############################################
# GLOBAL VARS
# - configure pbench_fio run settings
#----------------------------------------------
# Ceph related vars
cephServer="gprfc092"
pdsh_clients="gprfc[093-095]"
client_list="gprfc093 gprfc094 gprfc095"
basename_blk="/dev/rbd"
rbdPool_startindex=8           # first mapped: /dev/rbd8
rbdPool_endindex=67            # last mapped: /dev/rbd67
iscsiPool_startindex=68        # first mapped: /dev/rbd68
iscsiPool_endindex=127         # last mapped: /dev/rbd127

# FIO - for loop conditions (in order)
pool_list="iscsiTest rbdTest"
operation_list="randrw read"
ioengine_list="libaio"
ioengine="libaio"
blocksize_list="4k 1024k"
iodepth_list="8"
devcnt_list="1 5 20"            # number devices accessed/client

# Pbench FIO - GLOBAL section
samples=1
runtime=300
ramp=15
devsize=80g
#dir=/mnt/ceph/fio        # currently not used
log_avg=60000             # currently not used
log_hist=60000            # currently not used

# Paths & filenames
fio_basename="/tmp/fiojob."   # Unique jobfile per client
fio_tmp="/tmp/jobfile.fio"    # remote fio jobfile name
pbdir="/var/lib/pbench-agent"
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
  local pname=$2              # rbdTest

    if [ $ioengine == "rbd" ]; then
        io_str=$(printf "rbd\nclientname=admin\npool=${pname}\n")
    else
        io_str=${ioengine}
    fi

    cat <<EOF1 > ${fname}
[global]
group_reporting=1
time_based=1
runtime=${runtime}
clocksource=gettimeofday
ramp_time=${ramp}
ioengine=${io_str}
direct=1
bs=${bs}
iodepth=${iod}
rw=${oper}
rwmixread=80
size=${devsize}
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
    numclients=$(( numclients + 1 ))
    echo "${cl}" >> ${clientfile}
done

# Outer FOR Loop
for pool in $pool_list ; do
  # Name and create empty results directory
  rundate=`date +'%Y%m%d-%H%M'`
  testname="${rundate}_pbfio_${pool}"
  rundir="${pbdir}/${testname}"
  mkdir "${rundir}"

  # set offset for this pool
  if [ $pool == "rbdTest" ]; then
      start=$rbdPool_startindex
      end=$rbdPool_endindex
      pool_devcnt=$(( $end-$start ))
  else
      start=$iscsiPool_startindex
      end=$iscsiPool_endindex
      pool_devcnt=$(( $end-$start ))
  fi

  # populate the entire device list for this Pool
  declare -a devlist=()
  for ((i=$start; i<=$end; i++)); do
      devlist=("${devlist[@]}" "${basename_blk}${i}")
  done
#  echo "Number of elements in ${pool}: ${#devlist[@]}"
#  echo "${devlist[@]}"

  for oper in $operation_list ; do
     for bs in $blocksize_list; do
      for iod in $iodepth_list; do
        # INNER FOR LOOP
        #----------------------------------
        # Name and create the 'thistest' results directory
        thistest="${oper}_${bs}_${iod}"
        resultsdir="${rundir}/${thistest}"
        mkdir "${resultsdir}"

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
          declare -i devcnt=5  # this should be FOR loop'd
          stride=$(( $pool_devcnt % $numclients ))
          while [ $cnt -lt $devcnt ]; do
            cnt=$(( $cnt+1 ))
            x=$(( $x+$stride ))
            dev=${devlist[x]}
            job="${cl}-${ioengine}-${cnt}"
            # pass the fio, job and device names
            appendFIOjob ${fiofile} ${job} ${dev}
          done
          echo "${stride}"
          cat ${fiofile}
          exit
        done
        # FIO jobfiles written
        #----------------------------------
        # cat ${fiojob}
        # exit

        #-----------------------------------
        # Prepare for pbench-fio run
        # Drop caches on clients
        pdsh -S -w $pdsh_clients "sync ; \
          echo 3 > /proc/sys/vm/drop_caches" &> /dev/null
        sleep 5
        echo " ---> ${testname}" 

        # Start remote ceph watch
        ssh ${cephServer} "ceph -w > /tmp/ceph-watch &" &> /dev/null

        # Run pbench-fio
        #pbench-fio --samples=${samples} -t ${oper} -b ${bs} \
        #--client-file=${clientfile} --job-file=${fiojob} &> ${testname}.log

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
        pdsh -S -w $pdsh_clients "cat ${fio_tmp} > /tmp/fioHOLD.log"
        pdsh -S -w $pdsh_clients "fio ${fio_tmp} &>> /tmp/fioHOLD.log"

        # copy back and store the results
        for this_client in $client_list; do
            this_result="${resultsdir}/${this_client}.log"
            scp -q "${this_client}:/tmp/fioHOLD.log" ${this_result}
        done

        #----------------------------------
        # pbench-fio done - Cleanup and collect results
        # Stop remote ceph watch and copy results back
        cephwatch="${resultsdir}/ceph-watch"
        ssh ${cephServer} "pkill -f \"ceph -w\" "
        scp -q ${cephServer}:/tmp/ceph-watch ${cephwatch}

        # Move pbench-agent results dir and logfile to resultsdir
#        pbenchdir=`ls -rtd /var/lib/pbench-agent/fio_*/ |tail -1`
#        mv ${pbenchdir} ${resultsdir}
#        mv ${testname}.log ${resultsdir}
#        echo "pbenchdir: ${pbenchdir}"    # DEBUG
        echo "resultsdir: ${resultsdir}"  # DEBUG
        echo "cephwatch: ${cephwatch}"    # DEBUG
        #----------------------------------

      done  # end FOR $iod
     done   # end FOR $bs
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
