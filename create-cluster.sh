#! /bin/bash

# Regular Colors
Color_Off='\033[0m'       # Text Reset
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

# **************************************************************************** #
#                                  Utilities                                   #
# **************************************************************************** #

function usage () {
    echo "Usage: $0 [-n <k8s_namespace>] [-H <hostname>] [-C <cluster_name>] [-b <cc_image_repo>] [-i <cc_image_tag>] [-q <quorum_count>] [-m <manager_count>]"
    echo
    echo "-n    Specify desired kubernetes Namespace on which the instance will live (default is 'ns\$(date +%s)')"
    echo "      It must be a compliant DNS-1123 label and match =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"
    echo "      In practice, must consist of lower case alphanumeric characters or '-', and must start and end with an alphanumeric character"
    echo "-H    Specify the hostname of the worker node on which the GPFS cluster must be deployed (default is a random worker node)"
    echo "-C    Specify the name of the GPFS cluster to be deployed (default is 'gpfs\$(date +%s)')"
    echo "-b    Specify docker image repository to be used for the Pods creation (default is $CC_IMAGE_REPO)"
    echo "-i    Specify docker image tag to be used for the Pods creation (default is $CC_IMAGE_TAG)"
    echo "-q    Specify desired number of quorum servers (default is 1)"
    echo "-m    Specify desired number of manager servers (default is 1)"
    echo
    echo "-h    Show usage and exit"
    echo
}

function gen_role () {
    local role=$1
    local role_count=$2

    image_repo=$CC_IMAGE_REPO
    image_tag=$CC_IMAGE_TAG
    hostname=$HOST_NAME

    for i in $(seq 1 $role_count); do
        [[ -z $role_count ]] && i=""
        cp "$TEMPLATES_DIR/gpfs-${role}.template.yaml" "gpfs-${role}${i}.yaml"
        sed -i "s/%%%NAMESPACE%%%/${NAMESPACE}/g" "gpfs-${role}${i}.yaml"
        sed -i "s/%%%NUMBER%%%/${i}/g" "gpfs-${role}${i}.yaml"
        sed -i "s|%%%IMAGE_REPO%%%|${image_repo}|g" "gpfs-${role}${i}.yaml"
        sed -i "s/%%%IMAGE_TAG%%%/${image_tag}/g" "gpfs-${role}${i}.yaml"
        if [ -z "$hostname" ]; then
          workers=("ds-505" "ds-506" "ds-527" "ds-528")
          RANDOM=$$$(date +%s)
          selected_worker=${workers[ $RANDOM % ${#workers[@]} ]}
          sed -i "s/%%%NODENAME%%%/${selected_worker}.cr.cnaf.infn.it/g" "gpfs-${role}${i}.yaml"
        else
          sed -i "s/%%%NODENAME%%%/${hostname}.cr.cnaf.infn.it/g" "gpfs-${role}${i}.yaml"
        fi
        sed -i "s/%%%PODNAME%%%/${HOST_NAME}-gpfs-${role}-${i}/g" "gpfs-${role}${i}.yaml"
    done
}

function get_podname () {
    local app=$1
    kubectl get pods --namespace=$NAMESPACE -l app=$app | grep -E '([0-9]+)/\1' | awk '{print $1}' # Get only READY pods
}

function k8s-exec() {

    local namespace=$NAMESPACE
    local app=$1
    [[ $2 ]] && local k8cmd=${@:2}

    kubectl exec --namespace=$namespace $(kubectl get pods --namespace=$namespace -l app=$app | grep -E '([0-9]+)/\1' | awk '{print $1}') -- /bin/bash -c "$k8cmd"

}


# **************************************************************************** #
#                                  Entrypoint                                  #
# **************************************************************************** #

# defaults
NAMESPACE="ns$(date +%s)"
CLUSTER_NAME="gpfs$(date +%s)"
CC_IMAGE_REPO="tgagor/centos-stream"
CC_IMAGE_TAG="8"
MGR_COUNT=1
QRM_COUNT=1

while getopts 'n:C:H:b:i:q:m:h' opt; do
    case "${opt}" in
        n) # a DNS-1123 label must consist of lower case alphanumeric characters or '-', and must start and end with an alphanumeric character
            if [[ $OPTARG =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]];
                then NAMESPACE=${OPTARG}
                else echo "! Wrong arg -$opt"; exit 1
            fi ;;
        C) # a DNS-1123 label must consist of lower case alphanumeric characters or '-', and must start and end with an alphanumeric character
            if [[ $OPTARG =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]];
                then CLUSTER_NAME=${OPTARG}
                else echo "! Wrong arg -$opt"; exit 1
            fi ;;
        H)
            HOST_NAME=${OPTARG} ;;
        b)
            CC_IMAGE_REPO=${OPTARG} ;;
        i)
            CC_IMAGE_TAG=${OPTARG} ;;
        q) # quorum count must be an integer greater than 0
            if [[ $OPTARG =~ ^[0-9]+$ ]] && [[ $OPTARG -gt 0 ]]; then
                QRM_COUNT=${OPTARG}
            else
                echo "! Wrong arg -$opt"; exit 1
            fi ;;
        m) # mgr count must be an integer greater than 0
            if [[ $OPTARG =~ ^[0-9]+$ ]] && [[ $OPTARG -gt 0 ]]; then
                MGR_COUNT=${OPTARG}
                [[ $OPTARG -gt 1 ]] && with_qdb=true
            else
                echo "! Wrong arg -$opt"; exit 1
            fi ;;
        h)
            usage
            exit 0 ;;
        *)
            usage
            exit 1 ;;
    esac
done
shift $((OPTIND-1))

echo "NAMESPACE=$NAMESPACE"
echo "CLUSTER_NAME=$CLUSTER_NAME"
echo "CC_IMAGE_REPO=$CC_IMAGE_REPO"
echo "CC_IMAGE_TAG=$CC_IMAGE_TAG"
echo "QRM_COUNT=$QRM_COUNT"
echo "MGR_COUNT=$MGR_COUNT"


# **********************************************************************************************
# Generation of the K8s manifests and configuration scripts for a complete namespaced instance #
# **********************************************************************************************

TEMPLATES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/templates" # one-liner that gives the full directory name of the script no matter where it is being called from.
GPFS_INSTANCE_DIR="gpfs-instance-$NAMESPACE"
mkdir $GPFS_INSTANCE_DIR
cd $GPFS_INSTANCE_DIR


# Generate the namespace
cp "$TEMPLATES_DIR/namespace.template.yaml" "namespace-$NAMESPACE.yaml"
sed -i "s/%%%NAMESPACE%%%/$NAMESPACE/g" "namespace-$NAMESPACE.yaml"

# Generate the configmap files
cp "$TEMPLATES_DIR/init-configmap.template.yaml" "init-configmap.yaml"
sed -i "s/%%%NAMESPACE%%%/${NAMESPACE}/g" "init-configmap.yaml"

cp "$TEMPLATES_DIR/cluster-configmap.template.yaml" "cluster-configmap.yaml"
sed -i "s/%%%NAMESPACE%%%/${NAMESPACE}/g" "cluster-configmap.yaml"
for i in $(seq 1 $MGR_COUNT)
do
  echo "   ${HOST_NAME}-gpfs-mgr-$i-0:manager" | tee -a "cluster-configmap.yaml"
done
for i in $(seq 1 $QRM_COUNT)
do
  sed -i "s/${HOST_NAME}-gpfs-mgr-$i-0:manager/${HOST_NAME}-gpfs-mgr-$i-0:quorum-manager/" "cluster-configmap.yaml"
done

# Generate the external service
HOST_IP=$(nslookup $HOST_NAME | grep Address | tail -1 | awk '{print $2}')
cp "$TEMPLATES_DIR/external-svc.template.yaml" "external-svc.yaml"
sed -i "s/%%%NAMESPACE%%%/$NAMESPACE/g" "external-svc.yaml"
sed -i "s/%%%HOST_IP%%%/$HOST_IP/g" "external-svc.yaml"

# Generate the manifests
gen_role mgr $MGR_COUNT

# **********************************************************************************************
# Deploy the instance #
# **********************************************************************************************

shopt -s nullglob # The shopt -s nullglob will make the glob expand to nothing if there are no matches.
roles_yaml=(gpfs-*.yaml)

# Instantiate the namespace
kubectl apply -f "namespace-$NAMESPACE.yaml"
oc adm policy add-scc-to-user privileged -z default -n $NAMESPACE

# Instantiate the configmap
kubectl apply -f "init-configmap.yaml"
kubectl apply -f "cluster-configmap.yaml"

# Instantiate the external service
kubectl apply -f "external-svc.yaml"

# Conditionally split the pod creation in groups, since apparently the external provisioner (manila?) can't deal with too many volume-creation request per second
# [ $with_pvc == true ] && g=6 || g=${#roles_yaml[@]}
g=1
count=1;
for ((i=0; i < ${#roles_yaml[@]}; i+=g)); do
    j=`expr $i + 1`
    ssh $HOST_NAME -l core "sudo su - -c \"mkdir -p /root/client$j/var_mmfs\""
    ssh $HOST_NAME -l core "sudo su - -c \"mkdir -p /root/client$j/root_ssh\""
    ssh $HOST_NAME -l core "sudo su - -c \"mkdir -p /root/client$j/etc_ssh\""

    for p in ${roles_yaml[@]:i:g}; do
        kubectl apply -f $p;
    done

    podsReady=$(kubectl get pods --namespace=$NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' | grep -o "True" |  wc -l)
    podsReadyExpected=$(( $((i+g))<${#roles_yaml[@]} ? $((i+g)) : ${#roles_yaml[@]} ))
    # [ tty ] && tput sc @todo
    while [[ $count -le 600 ]] && [[ "$podsReady" -lt "$podsReadyExpected" ]]; do
        podsReady=$(kubectl get pods --namespace=$NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' | grep -o "True" | wc -l)
        if [[ $(($count%10)) == 0 ]]; then
            # [ tty ] && tput rc @todo
            echo -e "\n${Yellow} Current situation of pods: ${Color_Off}"
            kubectl get pods --namespace=$NAMESPACE
            if [[ $with_pvc == true ]]; then
                echo -e "${Yellow} and persistent volumes: ${Color_Off}"
                kubectl get pv --namespace=$NAMESPACE | grep "$NAMESPACE"
            fi
        fi
        echo -ne "\r Waiting $count secs for $podsReadyExpected pods to be Ready... $podsReady/$podsReadyExpected"
        sleep 1
        ((count+=1))
    done

done

if [[ $count -le 600 ]] ; then
    echo -e "${Green} OK, all the Pods are in Ready state! $podsReady/$podsReadyExpected ${Color_Off}"
else
    echo -e "${Red} KO, not all the Pods are in Ready state! $podsReady/$podsReadyExpected ${Color_Off}"
    exit 1
fi


# **********************************************************************************************
# Start the GPFS services in each Pod
# **********************************************************************************************

# Give the time to execute the readinessProbe, and so the eos-specific configuration of the containers
# kubectl wait pods --all --namespace $NAMESPACE --for=condition=Ready # @note experimental 'kubectl wait' command

echo "Starting the GPFS services in each Pod"

echo -e "${Yellow} Setup mutual Pods resolution on all the Pods... ${Color_Off}"

pods=(`kubectl -n $NAMESPACE get po | grep gpfs | awk '{print $1}'`)
for pod in ${pods[@]}
do
  printf '%s %s\n' "$(kubectl -n $NAMESPACE exec $pod -- bash -c 'cat /etc/hosts | grep gpfs | awk '"'"'{print $1}'"'"'')" \
  "$(kubectl -n $NAMESPACE exec $pod -- bash -c 'cat /etc/hosts | grep gpfs | awk '"'"'{print $2}'"'"'')" | \
  tee -a hosts.tmp
done
for pod in ${pods[@]}
do
  kubectl cp hosts.tmp $NAMESPACE/$pod:/tmp/hosts.tmp
  kubectl -n $NAMESPACE exec -it $pod -- bash -c "cp /etc/hosts hosts.tmp; sed -i \"$ d\" hosts.tmp; yes | cp hosts.tmp /etc/hosts; rm -f hosts.tmp"
  kubectl -n $NAMESPACE exec -it $pod -- bash -c 'cat /tmp/hosts.tmp >> /etc/hosts'
done
rm -f hosts.tmp

echo -e "${Yellow} Distribute SSH keys on all the Pods... ${Color_Off}"

pods=(`kubectl -n $NAMESPACE get po | grep gpfs | awk '{print $1}'`)
for pod in ${pods[@]}
do
  for i in $(seq 1 $MGR_COUNT)
  do
    ssh $HOST_NAME -l core "echo \""$(kubectl -n $NAMESPACE exec -it $pod -- bash -c "cat /root/.ssh/id_rsa.pub")"\" | sudo tee -a /root/client$i/root_ssh/authorized_keys"
  done
done
for pod1 in ${pods[@]}
do
  for pod2 in ${pods[@]}
  do
    kubectl -n $NAMESPACE exec -it $pod1 -- bash -c "ssh -o \"StrictHostKeyChecking=no\" $pod2 hostname"
  done
done

echo -e "${Yellow} Exec on quorum-manager (GPFS cluster setup)... ${Color_Off}"
k8s-exec gpfs-mgr1 "mmcrcluster -N /root/node.list -C ${CLUSTER_NAME} -r /usr/bin/ssh -R /usr/bin/scp --profile gpfsprotocoldefaults"
if [[ "$?" -ne 0 ]]; then exit 1; fi

echo -e "${Yellow} Exec on every GPFS quorum-manager... ${Color_Off}"
failure=0; pids="";
for i in $(seq 1 $MGR_COUNT); do
    k8s-exec gpfs-mgr${i} "mmstartup"
    pids="${pids} $!"
    sleep 0.1
done
for pid in ${pids}; do
  wait ${pid} || let "failure=1"
done
if [[ "${failure}" == "1" ]]; then
    echo -e "${Red} Failed to Exec on one of the managers ${Color_Off}"
    exit 1
fi

# @todo add error handling
echo -e "${Green} Exec went OK for all the Pods ${Color_Off}"


# Check status
k8s-exec gpfs-mgr1 "mmhealth cluster show"
for i in $(seq 1 $MGR_COUNT); do
    k8s-exec gpfs-mgr${i} "mmgetstate"
done

# print configuration summary
echo ""
echo "NAMESPACE=$NAMESPACE"
echo "CLUSTER_NAME=$CLUSTER_NAME"
echo "CC_IMAGE_REPO=$CC_IMAGE_REPO"
echo "CC_IMAGE_TAG=$CC_IMAGE_TAG"
echo "QRM_COUNT=$QRM_COUNT"
echo "MGR_COUNT=$MGR_COUNT"