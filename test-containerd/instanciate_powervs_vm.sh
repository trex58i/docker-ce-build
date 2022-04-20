#!/bin/bash

SSH_KEY=""
NAME=""
NETWORK=""
OUTPUT="."
RUNC_FLAVOR="runc"
TEST_RUNTIME="io.containerd.runc.v2"

set -euxo pipefail

function usage() {
	cat << EOF
The script creates a server, and runs tests with required options.
Usage: instanciate_powervs_vm.sh --key <SSH_KEY> --name <NAME> --network <NETWORK> [OPTIONS]
Options:
	--key <SSH_KEY>: name of the ssh key used;
	--name <NAME>: mandatory option, name without space;
	--network <NETWORK>: network used by PowerVS;
	--output <OUTPUT>: location to save results;
	--runc <RUNC_FLAVOR>: runc or crun (runc by default);
	--runtime <TEST_RUNTIME>: io.containerd.runtime.v1.linux,
		io.containerd.runc.v1 or io.containerd.runc.v2
		(io.containerd.runc.v2 by default);
EOF
}


# Get options
while [[ $# != 0 ]]; do
	case "$1" in
		--help | -h) usage; exit 0;;
		--key) SSH_KEY=$2; shift; shift;;
		--name) NAME=$2; shift; shift;;
		--network) NETWORK=$2; shift; shift;;
		--output) OUTPUT=$2; shift; shift;;
		--runc) RUNC_FLAVOR=$2; shift; shift;;
		--runtime) TEST_RUNTIME=$2; shift; shift;;
		*) echo "FAIL: Unknown argument $1"; usage; exit 1;;
	esac
done

# Ensure key, name and network are fulfilled
if [ -z $SSH_KEY ]; then echo "FAIL: Key not fulfilled."; usage; exit 1; fi
if [ -z $NAME ]; then echo "FAIL: Name not fulfilled."; usage; exit 1; fi
if [ -z $NETWORK ]; then echo "FAIL: Network not fulfilled."; usage; exit 1; fi

# Create a machine
# Sometime fail, but the machine is correctly instanciated
ibmcloud pi instance-create $NAME --image ubuntu_2004_containerd --key-name $SSH_KEY --memory 2 --processor-type shared --processors '0.25' --network $NETWORK --storage-type tier3 || true

# Wait it is registred
sleep 120
# Get PID
ID=$(ibmcloud pi ins | grep "$NAME" | cut -d ' ' -f1)

# If no ID, stop with error
if [ -z "$ID" ]; then echo "FAIL: fail to get ID. Probably VM has not started correctly."; exit 1; fi

# Using ID, get IP
# First, wait it starts
# Typical time needed: 5 to 6 minutes
TIMEOUT=10
i=0
while [ $i -lt $TIMEOUT ] && [ -z "$(ibmcloud pi in $ID | grep 'External Address:')" ]; do
  i=$((i+1))
  sleep 60
done
# Fail to connect
if [ "$i" == "$TIMEOUT" ]; then echo "FAIL: fail to get IP" ; exit 1; fi

IP=$(ibmcloud pi in $ID | grep -Eo "External Address:[[:space:]]*[0-9.]+" | cut -d ' ' -f3)

# Check if the server is up
# Typical time needed: 1 to 3 minutes
TIMEOUT=10
i=0
mkdir -p ~/.ssh
while [ $i -lt $TIMEOUT ] && ! ssh ubuntu@$IP -i /etc/ssh-volume/ssh-privatekey echo OK
do
  ssh-keyscan -t rsa $IP >> ~/.ssh/known_hosts
  i=$((i+1))
  sleep 60
done
# Fail to connect, try to reboot to bypass grub trouble
if [ "$i" == "$TIMEOUT" ]; then
  echo "Fail to get IP. Rebooting."
  ibmcloud pi insrb $ID
  # And try to connect again
  j=0
  while [ $j -lt $TIMEOUT ] && ! ssh ubuntu@$IP -i /etc/ssh-volume/ssh-privatekey echo OK
  do
    ssh-keyscan -t rsa $IP >> ~/.ssh/known_hosts
    j=$((j+1))
    sleep 60
  done
  # Fail again to connect
  if [ "$j" == "$TIMEOUT" ]; then echo "FAIL: fail to connect to the VM" ; exit 1; fi
fi

# Get test script and execute it
ssh ubuntu@$IP -i /etc/ssh-volume/ssh-privatekey wget https://raw.githubusercontent.com/ppc64le-cloud/docker-ce-build/main/test-containerd/test_on_powervs.sh
ssh ubuntu@$IP -i /etc/ssh-volume/ssh-privatekey sudo bash test_on_powervs.sh $RUNC_FLAVOR $TEST_RUNTIME
scp -i /etc/ssh-volume/ssh-privatekey "ubuntu@$IP:/home/containerd_test/containerd/*.xml" ${OUTPUT}

# Ensure we are yet connected
echo "" | ibmcloud login
# Remove machine after test
ibmcloud pi instance-delete $ID
