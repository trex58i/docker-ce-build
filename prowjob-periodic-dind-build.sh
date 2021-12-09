#!/bin/bash

set -ue

# Paths to the scripts and to the log
SECONDS=0
PATH_SCRIPTS="/home/prow/go/src/github.com/ppc64le-cloud/docker-ce-build"
DATE=`date +%d%m%y-%H%M`

if [[ -z ${ARTIFACTS} ]]
then
    ARTIFACTS=/logs/artifacts
    echo "Setting ARTIFACTS to ${ARTIFACTS}"
    mkdir -p ${ARTIFACTS}
fi
LOG="${ARTIFACTS}/prowjob_${DATE}.log"

export ARTIFACTS
export DATE
export PATH_SCRIPTS
export LOG

echo "Prow Job to build docker-ce" 2>&1 | tee ${LOG}

# Go to the workdir
cd /workspace

# Start the dockerd and wait for it to start
echo "* Starting dockerd and waiting for it *" 2>&1 | tee -a ${LOG}
source ${PATH_SCRIPTS}/dockerd-starting.sh

if [ -z "$pid" ]
then
    echo "There is no docker daemon." 2>&1 | tee -a ${LOG}
    exit 1
else
    # Get the env file and the dockertest repo and the latest built of containerd if we don't want to build containerd
    echo "** Set up (env files and dockertest) **" 2>&1 | tee -a ${LOG}
    source ${PATH_SCRIPTS}/get_env.sh

    set -o allexport
    source env.list
    source env-distrib.list

    # Build docker_ce and containerd and the static binaries
    echo "*** Build ***" 2>&1 | tee -a ${LOG}
    source ${PATH_SCRIPTS}/build.sh

    # Test the packages
    echo "*** * Tests * ***" 2>&1 | tee -a ${LOG}
    source ${PATH_SCRIPTS}/test.sh

    # Check if there are errors in the tests : NOERR or ERR
    echo "*** ** Tests check ** ***" 2>&1 | tee -a ${LOG}
    source ${PATH_SCRIPTS}/check_tests.sh
    echo "The tests results : ${CHECK_TESTS_BOOL}" 2>&1 | tee -a ${LOG}

    duration=$SECONDS
    echo "ALL : $(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed." 2>&1 | tee -a ${LOG}

    # Push to the COS Bucket according to CHECK_TESTS_BOOL
    echo "*** *** Push to the COS Buckets *** ***" 2>&1 | tee -a ${LOG}
    source ${PATH_SCRIPTS}/push_COS.sh
fi
