#!/bin/bash
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# BASH script to configure pbench on remote nodes
# run on ADMIN node

gateways="gprfc089 gprfc090"
clients="gprfc093 gprfc094 gprfc095"
osds="gprfs041 gprfs042 gprfs044"
mon="gprfc092"

iostat_list="${clients} ${osds}"
sar_list="${iostat_list} ${gateways} ${mon}"

##############################################
# SCRIPT
#----------------------------------------------

for host in $iostat_list; do
  pbench-register-tool --remote="${host}" --name=iostat -- --interval=10
done

for host in $sar_list; do
  pbench-register-tool --remote="${host}" --name=sar -- --interval=10
done


