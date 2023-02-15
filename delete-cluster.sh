#!/bin/bash
# **************************************************************************** #
#                                  Entrypoint                                  #
# **************************************************************************** #

if [ "$#" -lt 1 ]; then
    echo "ERROR: Illegal number of parameters. Syntax: $0 <k8s-namespace>"
    exit 1
fi

namespace=$1
NSD_FILE=./gpfs-instance-$namespace/nsd-configmap.yaml
if [ -f "$NSD_FILE" ]; then
  POD_NAME=$(kubectl -n $namespace get po -lapp=gpfs-mgr1 -ojsonpath="{.items[*].metadata.name}")
  FS_NAME=$(kubectl -n $namespace exec $POD_NAME -- /usr/lpp/mmfs/bin/mmlsmount all_local | awk '{print $3}')
  kubectl -n $namespace exec $POD_NAME -- /usr/lpp/mmfs/bin/mmumount all -a
  kubectl -n $namespace exec $POD_NAME -- /usr/lpp/mmfs/bin/mmdelfs $FS_NAME -p
  kubectl -n $namespace exec $POD_NAME -- /usr/lpp/mmfs/bin/mmdelnsd -F /tmp/StanzaFile
fi
kubectl delete ns $namespace
HOST_NAME=$(cat ./gpfs-instance-$namespace/gpfs-mgr1.yaml | grep nodeName | awk '{print $2}')
ssh $HOST_NAME -l core "sudo su - -c \"rm -rf /root/client*\""
rm -rf "./gpfs-instance-$namespace"
