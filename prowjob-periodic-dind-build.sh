#!/bin/bash

set -ue

# path to the scripts 
PATH_SCRIPTS="/home/prow/go/src/github.com/ppc64le-cloud/docker-ce-build"
LOG="/workspace/prowjob.log"

export PATH_SCRIPTS
export LOG

echo "PROW JOB" 2>&1 | tee ${LOG}

mkdir -p /home/prow/go/src/github.com/ppc64le-cloud
cd /home/prow/go/src/github.com/ppc64le-cloud
git clone https://github.com/florencepascual/docker-ce-build.git

wget -O ${PATH_SCRIPTS}/dockerd-entrypoint.sh https://raw.githubusercontent.com/docker-library/docker/master/dockerd-entrypoint.sh 
if ! test -f ${PATH_SCRIPTS}/dockerd-entrypoint.sh
then
    echo "The dockerd-entrypoint file was not downloaded." 2>&1 | tee -a ${LOG}
    exit 1
fi

chmod a+x ${PATH_SCRIPTS}/*.sh
cd /workspace

# start the dockerd and wait for it to start
echo "* Starting dockerd *" 2>&1 | tee -a ${LOG}
bash ${PATH_SCRIPTS}/dockerd-entrypoint.sh &
source ${PATH_SCRIPTS}/dockerd-waiting.sh

if [ -z "$pid" ]
then
    echo "There is no docker daemon." 2>&1 | tee -a ${LOG}
    exit 1
else
    # get the env file and the dockertest repo and the latest built of containerd if we don't want to build containerd
    echo "*** COS Bucket ***" 2>&1 | tee -a ${LOG}
    source ${PATH_SCRIPTS}/get_env.sh
    if [[ $? -ne 0 ]]
    then
        echo "The script to get the env.list, the env-distrib.list and the dockertest has failed." 2>&1 | tee -a ${LOG}
        exit 1
    fi

    set -o allexport
    source env.list
    source env-distrib.list

    # build docker_ce and containerd
    echo "*** ** BUILD ** ***" 2>&1 | tee -a ${LOG}
    source ${PATH_SCRIPTS}/build.sh 
    if [[ $? -ne 0 ]]
    then
        echo "The script supposed to build the packages has failed." 2>&1 | tee -a ${LOG}
        exit 1
    fi

    # test the packages
    echo "*** *** TEST *** ***" 2>&1 | tee -a ${LOG}
    source ${PATH_SCRIPTS}/test.sh
    if [[ $? -ne 0 ]]
    then
        echo "We have not been able to check the tests." 2>&1 | tee -a ${LOG}
        exit 1
    else
        echo "*** *** * TESTS CHECK * *** ***" 2>&1 | tee -a ${LOG}
        source ${PATH_SCRIPTS}/check_tests.sh
        echo "The tests results : ${CHECK_TESTS_BOOL}" 2>&1 | tee -a ${LOG}
    fi

    # push to the COS Bucket
    echo "*** *** ** COS Bucket ** *** ***" 2>&1 | tee -a ${LOG}
    source ${PATH_SCRIPTS}/push_COS.sh

    if [[ $? -ne 0 ]]
    then
        echo "The docker to push the packages and/or the tests has failed."
        exit 1
    else 
        echo "The packages and/or the tests have been pushed."
        exit 0
    fi
fi
