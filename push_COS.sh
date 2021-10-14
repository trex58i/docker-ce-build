#!/bin/bash

# if no error push to cos ibm-docker-builds and push to ppc64le-docker and delete the last version in ppc64le-docker, push log
# if errors, push only to ppc64le-docker but don't delete last version and push log

# ${CHECK_TESTS_BOOL} -> ERR or NOERR

set -ue

PATH_COS="/mnt"
PATH_PASSWORD=".s3fs_cos_secret"

COS_BUCKET_SHARED="ibm-docker-builds"
URL_COS_SHARED="https://s3.us-east.cloud-object-storage.appdomain.cloud"

COS_BUCKET_PRIVATE="ppc64le-docker"
URL_COS_PRIVATE="https://s3.us-south.cloud-object-storage.appdomain.cloud"

echo ":" > ${PATH_PASSWORD}_buffer
echo "$S3_SECRET_AUTH" >> ${PATH_PASSWORD}_buffer
tr -d '\n' < ${PATH_PASSWORD}_buffer > ${PATH_PASSWORD}
chmod 600 ${PATH_PASSWORD}
rm ${PATH_PASSWORD}_buffer

# ppc64le-docker
if ! test -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}
then
    mkdir -p ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}
    # mount the cos bucket
    s3fs ${COS_BUCKET_PRIVATE} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE} -o url=${URL_COS_PRIVATE} -o passwd_file=${PATH_PASSWORD} -o ibm_iam_auth
fi

# if there are no errors
if [[ ${CHECK_TESTS_BOOL} == "NOERR" ]]
then
    echo "- NOERR ppc64le-docker -" 2>&1 | tee -a ${LOG}
    # delete the last packages (both if CONTAINERD_VERS != 0)
    # remove last version of docker-ce and last tests and last log
    # rm -rf ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/docker-ce-*
    # rm -rf ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/test_*
    # rm -rf ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/prow-job-*
    echo "${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/docker-ce-* deleted" 2>&1 | tee -a ${LOG}
    echo "${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/test_* deleted" 2>&1 | tee -a ${LOG}
    echo "${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/prow-job-* deleted" 2>&1 | tee -a ${LOG}

    if [[ ${CONTAINERD_VERS} != "0" ]]
    # if CONTAINERD_VERS contains a version of containerd
    then
        # remove last version of containerd and last tests
        # rm -rf ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/containerd-*
        echo "${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/containerd-* deleted" 2>&1 | tee -a ${LOG}
    fi

    # ibm-docker-builds
    echo "- NOERR ibm-docker-builds -" 2>&1 | tee -a ${LOG}

    mkdir -p ${PATH_COS}/s3_${COS_BUCKET_SHARED}
    # mount the cos bucket
    s3fs ${COS_BUCKET_SHARED} ${PATH_COS}/s3_${COS_BUCKET_SHARED} -o url=${URL_COS_SHARED} -o passwd_file=${PATH_PASSWORD} -o ibm_iam_auth
    
    # copy the builds into the COS Bucket ibm-docker-builds
    # get the directory name "docker-ce-20.10-11" version without patch number then build tag
    DIR_DOCKER_VERS=$(eval "echo ${DOCKER_VERS} | cut -d'v' -f2 | cut -d'.' -f1-2")
    ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/docker-ce-*/
    if [[ $? -eq 0 ]]
    then
        DOCKER_LAST_BUILD_TAG=$(ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/docker-ce-${DIR_DOCKER_VERS}-* | sort --version-sort | tail -1| cut -d'-' -f6)
        DOCKER_BUILD_TAG=$((DOCKER_LAST_BUILD_TAG+1))
    else 
        # there are no directories yet
        DOCKER_BUILD_TAG="1"
    fi
    DIR_DOCKER_SHARED=docker-ce-${DIR_DOCKER_VERS}-${DOCKER_BUILD_TAG}
    # copy the package to the cos bucket
    # cp -r /workspace/docker-ce-* ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_DOCKER_SHARED}
    echo "${DIR_DOCKER_SHARED} copied" 2>&1 | tee -a ${LOG}
    echo "build tag ${DOCKER_BUILD_TAG}" 2>&1 | tee -a ${LOG}

    if [[ ${CONTAINERD_VERS} != "0" ]]
    then
        # get the directory name "containerd-1.4-9" version without patch number then build tag
        DIR_CONTAINERD_VERS=$(eval "echo ${CONTAINERD_VERS} | cut -d'v' -f2 | cut -d'.' -f1-2")

        ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/containerd-*/
        if [[ $? -eq 0 ]]
        then
            CONTAINERD_LAST_BUILD_TAG=$(ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/containerd-${DIR_CONTAINERD_VERS}-* | sort --version-sort | tail -1| cut -d'-' -f5)
            CONTAINERD_BUILD_TAG=$((CONTAINERD_LAST_BUILD_TAG+1))
        else
            # there are no directories yet
            CONTAINERD_BUILD_TAG="1"
        fi
        DIR_CONTAINERD=containerd-${DIR_CONTAINERD_VERS}-${CONTAINERD_BUILD_TAG}
        # copy the package to the cos bucket
        # cp -r /workspace/containerd-* ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}
        echo "${DIR_CONTAINERD} copied" 2>&1 | tee -a ${LOG}
        echo "build tag ${CONTAINERD_BUILD_TAG}" 2>&1 | tee -a ${LOG}
    fi
fi

echo "-- ERR and NOERR ppc64le-docker --" 2>&1 | tee -a ${LOG}

# !!! TEST !!!
mkdir -p ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}

# push log
cp ${LOG} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
cp /workspace/static.log ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}

# push packages, no matter what ${CHECK_TESTS_BOOL} is
ls -d /workspace/docker-ce-${DOCKER_VERS}
if [[ $? -eq 0 ]]
# copy the builds into the COS Bucket ppc64le-docker, the tests and the log
then
    DIR_DOCKER_PRIVATE=docker-ce-${DOCKER_VERS}
    mkdir ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/${DIR_DOCKER_PRIVATE}
    
    # !!! TEST !!!
    cp -r /workspace/docker-ce-${DOCKER_VERS} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/${DIR_DOCKER_PRIVATE}
    if test -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/${DIR_DOCKER_PRIVATE}
    then
        echo "${DIR_DOCKER_PRIVATE} copied" 2>&1 | tee -a ${LOG}
    fi

    cp -r /workspace/test_* ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/
    if test -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/test_*
    then
        echo "/workspace/test_* copied" 2>&1 | tee -a ${LOG}
    fi

    if test -f ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
    then
        echo "/workspace/prowjob.log copied" 2>&1 | tee -a ${LOG}
    fi
else
    echo "There are no docker-ce packages." 2>&1 | tee -a ${LOG}
fi

if [[ ${CONTAINERD_VERS} != "0" ]]
# if CONTAINERD_VERS contains a version of containerd
then
    ls -d /workspace/containerd-${CONTAINERD_VERS}
    # copy the builds in the COS bucket ppc64le-docker
    if [[ $? -eq 0 ]]
    then
        DIR_CONTAINERD_PRIVATE=containerd-${CONTAINERD_VERS}
        # !!! TEST !!!
        cp -r /workspace/containerd-${CONTAINERD_VERS} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/${DIR_CONTAINERD_PRIVATE}
        if test -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/${DIR_CONTAINERD_PRIVATE}
        then
            echo "${DIR_CONTAINERD_PRIVATE} copied" 2>&1 | tee -a ${LOG}
        fi
    else
        # there are no directories yet
        CONTAINERD_BUILD_TAG="1"
    fi
else 
    echo "There are no containerd packages." 2>&1 | tee -a ${LOG}
fi

# check if pushed to COS Buckets and stop the container

# !!! TEST !! 
# check TEST dir in ppc64le-docker
# check ibm-docker-builds mnt 

ls ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/*
if [[ $? -eq 0 ]]
then
    echo "Packages in the private COS Bucket" 2>&1 | tee -a ${LOG}
    BOOL_PRIVATE=0
    
else
    echo "Packages not in the private COS Bucket" 2>&1 | tee -a ${LOG}
    exit 1
fi

if [[ ${CHECK_TESTS_BOOL} == "NOERR" ]]
then
    if test -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}
    then
        ls ${PATH_COS}/s3_${COS_BUCKET_SHARED}
        echo "No error in the tests and shared bucket mounted." 2>&1 | tee -a ${LOG}
    else 
        echo "No error in the tests but shared bucket not mounted." 2>&1 | tee -a ${LOG}
        exit 1
    fi
else
    echo "There were some errors in the test, the packages have been pushed only to the private COS Bucket." 2>&1 | tee -a ${LOG}
fi