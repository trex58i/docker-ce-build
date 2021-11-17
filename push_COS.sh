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

PATH_DISTROS_MISSING="/workspace/distros-missing.txt"

# If there are no errors
if [[ ${CHECK_TESTS_BOOL} == "NOERR" ]]
then
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
    # cp -r /workspace/docker-ce-${DOCKER_VERS}_${DATE} ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_DOCKER_SHARED}
    echo "${DIR_DOCKER_SHARED} copied" 2>&1 | tee -a ${LOG}
    echo "Build tag ${DOCKER_BUILD_TAG}" 2>&1 | tee -a ${LOG}

    if [[ ${CONTAINERD_BUILD} -eq "1" ]]
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
        # mkdir ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}

        # Copy the containerd packages to the COS bucket
        # cp -r /workspace/containerd-${CONTAINERD_VERS}_${DATE} ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}
        echo "${DIR_CONTAINERD} copied" 2>&1 | tee -a ${LOG}
        echo "Build tag ${CONTAINERD_BUILD_TAG}" 2>&1 | tee -a ${LOG}
    else
        # check if distros-missing.txt exists and if exists, push only the distros mentionned
        if test -f ${PATH_DISTROS_MISSING}
        then
            # We built some distros
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
            # mkdir ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}

            while read -r line
            do
                # Copy the containerd package
                DISTRO_NAME="$(cut -d':' -f1 <<<"${line}")"
                DISTRO_VERS="$(cut -d':' -f2 <<<"${line}")"
                # cp -r /workspace/containerd-${CONTAINERD_VERS}_${DATE}/${DISTRO_NAME}/${DISTRO_VERS}
                echo "${DIR_CONTAINERD} copied" 2>&1 | tee -a ${LOG}
                echo "Build tag ${CONTAINERD_BUILD_TAG}" 2>&1 | tee -a ${LOG}
            done
        fi
    fi
fi

if [[ ${CHECK_TESTS_BOOL} == "NOERR" ]]
then
    if test -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}
    then
        ls ${PATH_COS}/s3_${COS_BUCKET_SHARED}
        echo "No error in the tests and shared bucket mounted." 2>&1 | tee -a ${LOG}
        exit 0
    else
        echo "No error in the tests but shared bucket not mounted." 2>&1 | tee -a ${LOG}
        exit 1
    fi
else
    echo "There were some errors in the test, the packages have been pushed only to the private COS Bucket." 2>&1 | tee -a ${LOG}
    exit 1
fi
