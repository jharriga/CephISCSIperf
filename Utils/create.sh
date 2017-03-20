#!/bin/bash
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# BASH script to automate configuration of RBD and ISCSI 
# comparision testing

cephPG=4096
cephPGP=4096
devcnt=60         # how many devices per pool 
img_size="100G"
poolname_list="rbdTest iscsiTest"
client_list="gprfc093 gprfc094 gprfc095"
allocation_host="gprfc089"

#--------------------------------------------------
# Create pool 
# Requires one passed arg - poolname
# - first ensure it does not already exist (unlikely)
# - allow user to remove if it exists 
function createPool {
    local name=$1

    if (ceph osd lspools | egrep -e ${name}) ; then
      echo "WARNING: pool ${name} exists..."
      echo "> would you like me to delete it? (Yes/No)"
      select yn in "Yes" "No"; do
          case $yn in
              Yes ) ceph osd pool delete ${name} ${name} --yes-i-really-really-mean-it; break;;
              No ) echo "please manually delete pool ${name}. Exiting."; exit;;
          esac
      done
    fi

    ceph osd pool create ${name} ${cephPG} ${cephPGP} replicated
}   # END createPool

#--------------------------------
# Create RBD devices. 
# Requires two passed arg: 
#   $1 = number of devices to create
#   $2 = poolname
function createRBD {
    local cnt=$1
    local pname=$2
    for (( i=1; i<=${cnt}; i++ )); do
      img_name="${pname}-${i}"
      rbd create ${img_name} --size ${img_size} --pool ${pname} \
        --image-format 2 --image-feature exclusive-lock \
        --image-feature layering
    done
}    # END createRBD

#--------------------------------
# Create and echo iSCSI Gateway configuration text. 
# Requires two passed arg: 
#   $1 = number of devices to create
#   $2 = poolname
#   $3 = number of clients
function echoGWlines {
  local cnt=$1
  local pname=$2
  local numcl=$3

  declare -i start=1
  declare -i end=0
  declare -i loopcntr=0
  declare -A img_array=()
  declare -i clindex=0
  declare -i imgindex=0

  clcnt=$(( cnt/numcl ))        # how many per client

  echo "Content for the /usr/share/ceph-ansible/group_vars/ceph-iscsi-gw file"
  echo "Paste into rbd_devices:"
  for cl in $client_list; do
    imgindex=0
#    start=$start
#    end=$(( $start+$clcnt ))
    for (( i=1; i<=$clcnt; i++ )); do
      imgname="${cl}-${pname}-${i}"
#      echo "  - { pool: '${pname}', image: '${imgname}', size: '${img_size}', host: \"{{ allocation_host }}\", state: 'present' }"
      echo "  - { pool: '${pname}', image: '${imgname}', size: '${img_size}', host: '${allocation_host}', state: 'present' }"
      img_array[$clindex,$imgindex]="${imgname}"
      imgindex=$(( $imgindex+1 ))
    done
#    start=$(( $start+$clcnt ))
    clindex=$(( $clindex+1 ))
  done
  echo "----------------------------"
  # echo out the line 
  # note syntax on ${img_list%?} strips off final character (comma)
  echo "Paste into client_connections:"
  n=0
  for cl in $client_list; do
    img_list=""
    chap_uname="${cl}"
    chap_pass="redhat"
    for (( m=0; m<$clcnt; m++ )); do
      img_list+="${pname}.${img_array[$n,$m]}"
      img_list+=","
    done
#    echo "  - { client: 'iqn.1994-05.com.redhat:rh7-iscsi-client', image_list: '${img_list%?}', chap: '${chap_uname}/${chap_pass}', status: 'present' }"
# use per client named IQN
    echo "  - { client: 'iqn.1994-05.com.redhat:${cl}', image_list: '${img_list%?}', chap: '${chap_uname}/${chap_pass}', status: 'present' }"
    n=$(( $n+1 ))
  done

}     # END echoGWlines
#
#----------------------------------------------
# END FUNCTIONS
##############################################

##############################################
# SCRIPT
#----------------------------------------------
echo "Start: " `date`

# Create pools
for poolname in ${poolname_list}; do
    createPool ${poolname}
    echo -n
done

createRBD ${devcnt} rbdTest

echoGWlines ${devcnt} iscsiTest 3

echo "----------------------------"
echo "Completed: " `date`

