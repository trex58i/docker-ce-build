#!/bin/bash
# Script to push to the COS buckets
# ${CHECK_TESTS_BOOL} -> ERR or NOERR
# if NOERR (there are no errors) : push to both COS buckets (ibm-docker-builds and ppc64le-docker) and delete the last versions that were at the beginning in the ppc64le-docker COS bucket
# if ERR (there are errors) : push only to ppc64le-docker but don't delete the last versions that were at the beginning in the ppc64le-docker COS bucket

set -ue

PATH_COS="/mnt"
PATH_PASSWORD="${PATH_SCRIPTS}/.s3fs_cos_secret"

COS_BUCKET_SHARED="ibm-docker-builds"
URL_COS_SHARED="https://s3.us-east.cloud-object-storage.appdomain.cloud"

COS_BUCKET_PRIVATE="ppc64le-docker"
URL_COS_PRIVATE="https://s3.us-south.cloud-object-storage.appdomain.cloud"

# Set up the s3 secret if not already configured
if ! test -f ${PATH_PASSWORD}
then
    echo ":${S3_SECRET_AUTH}" > ${PATH_PASSWORD}
    chmod 600 ${PATH_PASSWORD}
fi

# Mount the ppc64le-docker COS bucket if not already mounted
if ! test -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}
then
    mkdir -p ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}
    # Mount the COS bucket
    s3fs ${COS_BUCKET_PRIVATE} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE} -o url=${URL_COS_PRIVATE} -o passwd_file=${PATH_PASSWORD} -o ibm_iam_auth
fi

# If there are no errors
if [[ ${CHECK_TESTS_BOOL} == "NOERR" ]]
then
    echo "- NOERR ppc64le-docker -" 2>&1 | tee -a ${LOG}
    # Remove the last version of docker-ce, the last tests and the last log
    # rm -rf ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/docker-ce-*
    echo "${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/docker-ce-* deleted" 2>&1 | tee -a ${LOG}
    # rm -rf ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/test_*
    echo "${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/test_* deleted" 2>&1 | tee -a ${LOG}
    # rm -rf ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/prowjob-*
    echo "${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/prowjob* deleted" 2>&1 | tee -a ${LOG}

    ls -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/containerd-${CONTAINERD_VERS}
    if [[ $? -ne 0 ]]
    then
        # We built a new version of containerd
        # Remove the last version of containerd
        # rm -rf ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/containerd-*
        echo "${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/containerd-* deleted" 2>&1 | tee -a ${LOG}
    fi

    echo "- NOERR ibm-docker-builds -" 2>&1 | tee -a ${LOG}

    # Mount the ibm-docker-builds COS bucket
    mkdir -p ${PATH_COS}/s3_${COS_BUCKET_SHARED}
    # Mount the COS bucket
    s3fs ${COS_BUCKET_SHARED} ${PATH_COS}/s3_${COS_BUCKET_SHARED} -o url=${URL_COS_SHARED} -o passwd_file=${PATH_PASSWORD} -o ibm_iam_auth

    # Copy the docker-ce packages into the COS Bucket ibm-docker-builds
    # Get the directory name ex: "docker-ce-20.10-11" (version without patch number then build tag)
    DIR_DOCKER_VERS=$(eval "echo ${DOCKER_VERS} | cut -d'v' -f2 | cut -d'.' -f1-2")
    ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/docker-ce-*/
    if [[ $? -eq 0 ]]
    then
        DOCKER_LAST_BUILD_TAG=$(ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/docker-ce-${DIR_DOCKER_VERS}-* | sort --version-sort | tail -1| cut -d'-' -f6)
        DOCKER_BUILD_TAG=$((DOCKER_LAST_BUILD_TAG+1))
    else
        # If there are no directories yet
        DOCKER_BUILD_TAG="1"
    fi
    DIR_DOCKER_SHARED=docker-ce-${DIR_DOCKER_VERS}-${DOCKER_BUILD_TAG}

    # Copy the docker-ce packages to the COS bucket
    # cp -r /workspace/docker-ce-* ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_DOCKER_SHARED}
    echo "${DIR_DOCKER_SHARED} copied" 2>&1 | tee -a ${LOG}
    echo "Build tag ${DOCKER_BUILD_TAG}" 2>&1 | tee -a ${LOG}

    ls -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/containerd-*
    if [[ $? -ne 0 ]]
    then
        # We built a new version of containerd
        # Copy the new version of containerd into the COS bucket ibm-docker-builds
        # Get the directory name ex: "containerd-1.4-9" (version without patch number then build tag)
        DIR_CONTAINERD_VERS=$(eval "echo ${CONTAINERD_VERS} | cut -d'v' -f2 | cut -d'.' -f1-2")

        ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/containerd-*/
        if [[ $? -eq 0 ]]
        then
            CONTAINERD_LAST_BUILD_TAG=$(ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/containerd-${DIR_CONTAINERD_VERS}-* | sort --version-sort | tail -1| cut -d'-' -f5)
            CONTAINERD_BUILD_TAG=$((CONTAINERD_LAST_BUILD_TAG+1))
        else
            # If there are no directories yet
            CONTAINERD_BUILD_TAG="1"
        fi
        DIR_CONTAINERD=containerd-${DIR_CONTAINERD_VERS}-${CONTAINERD_BUILD_TAG}
        # Copy the containerd packages to the COS bucket
        # cp -r /workspace/containerd-* ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}
        echo "${DIR_CONTAINERD} copied" 2>&1 | tee -a ${LOG}
        echo "Build tag ${CONTAINERD_BUILD_TAG}" 2>&1 | tee -a ${LOG}
    fi
fi

# Common tasks to both COS buckets
echo "-- ERR and NOERR ppc64le-docker --" 2>&1 | tee -a ${LOG}

# !!! TEST !!!
mkdir -p ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}

# Push packages, no matter what ${CHECK_TESTS_BOOL} is
if test -d /workspace/docker-ce-${DOCKER_VERS}
then
    # Copy the docker-ce packages into the ppc64le-docker COS bucket and the tests
    DIR_DOCKER_PRIVATE=docker-ce-${DOCKER_VERS}
    mkdir ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/${DIR_DOCKER_PRIVATE}

    # !!! TEST !!!
    # Push the docker-ce packages
    cp -r /workspace/docker-ce-${DOCKER_VERS} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}
    if test -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/${DIR_DOCKER_PRIVATE}
    then
        echo "${DIR_DOCKER_PRIVATE} copied" 2>&1 | tee -a ${LOG}
    fi

    # Push the tests
    cp -r /workspace/test_* ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/
    if test -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/test_*
    then
        echo "/workspace/test_* copied" 2>&1 | tee -a ${LOG}
    fi

    # Push the static log
    cp /workspace/static.log ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}
    if test -f ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/static.log
    then
        echo "/workspace/static.log copied" 2>&1 | tee -a ${LOG}
    fi
else
    echo "There are no docker-ce packages." 2>&1 | tee -a ${LOG}
fi

ls -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/containerd-*
if [[ $? -ne 0 ]]
then
    # We built a new version of containerd
    # Copy the containerd packages to the ppc64le-docker COS bucket
    ls -d /workspace/containerd-${CONTAINERD_VERS}
    if [[ $? -eq 0 ]]
    then
        # !!! TEST !!!
        cp -r /workspace/containerd-${CONTAINERD_VERS} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}
        if test -d ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/containerd-${CONTAINERD_VERS}
        then
            echo "containerd-${CONTAINERD_VERS} copied" 2>&1 | tee -a ${LOG}
        fi
    fi
fi

# Check if we pushed to the COS buckets and stop the container

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
    # Push the prowjob.log
    cp ${LOG} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
    if test -f ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
    then
        echo "/workspace/prowjob.log copied" 2>&1 | tee -a ${LOG}
    fi
    exit 1
fi

if [[ ${CHECK_TESTS_BOOL} == "NOERR" ]]
then
    if test -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}
    then
        ls ${PATH_COS}/s3_${COS_BUCKET_SHARED}
        echo "No error in the tests and shared bucket mounted." 2>&1 | tee -a ${LOG}
        BOOL_SHARED=0
    else
        echo "No error in the tests but shared bucket not mounted." 2>&1 | tee -a ${LOG}
        # Push the prowjob.log
        cp ${LOG} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
        if test -f ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
        then
            echo "/workspace/prowjob.log copied" 2>&1 | tee -a ${LOG}
        fi
        exit 1
    fi
else
    echo "There were some errors in the test, the packages have been pushed only to the private COS Bucket." 2>&1 | tee -a ${LOG}
    # Push the prowjob.log
    cp ${LOG} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
    if test -f ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
    then
        echo "/workspace/prowjob.log copied" 2>&1 | tee -a ${LOG}
    fi
    exit 1
fi

if [[ ${BOOL_PRIVATE} -eq 0 ]] && [[ ${BOOL_SHARED} -eq 0 ]]
then
    echo "Packages in the private COS bucjet and no error in the tests and shared bucket mounted"
    # Push the prowjob.log
    cp ${LOG} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
    if test -f ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/TEST_${DOCKER_VERS}/prowjob.log
    then
        echo "/workspace/prowjob.log copied" 2>&1 | tee -a ${LOG}
    fi
    exit 0
fi
