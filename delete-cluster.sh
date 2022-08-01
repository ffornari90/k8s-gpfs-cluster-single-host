#!/bin/bash
# **************************************************************************** #
#                                  Entrypoint                                  #
# **************************************************************************** #

if [ "$#" -lt 1 ]; then
    echo "ERROR: Illegal number of parameters. Syntax: $0 <k8s-namespace>"
    exit 1
fi

namespace=$1

kubectl delete ns $namespace
HOST_NAME=$(cat ./gpfs-instance-$namespace/gpfs-mgr1.yaml | grep nodeName | awk '{print $2}')
ssh $HOST_NAME -l core "sudo su - -c \"rm -rf /root/client*\""
rm -rf "./gpfs-instance-$namespace"
