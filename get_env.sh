#!/bin/bash
# Script to get the env.list file and the dockertest from the ppc64le-docker COS bucket and to generate the env-distrib.list
# The env.list would contain the DOCKER_VERS, the CONTAINERD_VERS and the PACKAGING_REF which is the commit for the docker-ce-packaging repo
# The env-distrib.list would get the distributions for which we want to build docker-ce

set -ue

PATH_COS="/mnt"
PATH_PASSWORD="${PATH_SCRIPTS}/.s3fs_cos_secret"

COS_BUCKET_PRIVATE="ppc64le-docker"
URL_COS_PRIVATE="https://s3.us-south.cloud-object-storage.appdomain.cloud"

FILE_ENV="env.list"
FILE_ENV_DISTRIB="env-distrib.list"
PATH_DOCKERTEST="/workspace/test/src/github.ibm.com/powercloud"

# Set up the s3 secret if not already configured
if ! test -f ${PATH_PASSWORD}
then
    echo ":${S3_SECRET_AUTH}" > ${PATH_PASSWORD}
    chmod 600 ${PATH_PASSWORD}
fi

# Mount the COS bucket
mkdir -p ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}
s3fs ${COS_BUCKET_PRIVATE} ${PATH_COS}/s3_${COS_BUCKET_PRIVATE} -o url=${URL_COS_PRIVATE} -o passwd_file=${PATH_PASSWORD} -o ibm_iam_auth

# Copy the env.list to the local /workspace
cp ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/${FILE_ENV} /workspace/${FILE_ENV}

# Copy the dockertest repo to the local /workspace
mkdir -p ${PATH_DOCKERTEST}
cp -r ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/dockertest ${PATH_DOCKERTEST}/dockertest

set -o allexport
source /workspace/${FILE_ENV}

# Generate env-distrib.list
mkdir docker-ce-packaging
pushd docker-ce-packaging
git init
git remote add origin  https://github.com/docker/docker-ce-packaging.git
git fetch --depth 1 origin ${PACKAGING_REF}
git checkout FETCH_HEAD

make REF=${DOCKER_VERS} checkout
popd

# Get the distributions list in the docker-ce-packaging repository
echo DEBS=\"`cd docker-ce-packaging/deb && ls -1d debian-* ubuntu-*`\" > ${FILE_ENV_DISTRIB}
echo RPMS=\"`cd docker-ce-packaging/rpm && ls -1d centos-* fedora-*`\" >> ${FILE_ENV_DISTRIB}

source /workspace/${FILE_ENV_DISTRIB}

# Get the containerd directory if we don't want to build containerd
if [[ ${CONTAINERD_VERS} = "0" ]]
then
    cp -r ${PATH_COS}/s3_${COS_BUCKET_PRIVATE}/prow-docker/containerd-* /workspace/
fi

# Check if we have the env.list, the env-distrib.list and the dockertest
if ! test -f /workspace/${FILE_ENV} && test -d ${PATH_DOCKERTEST}/dockertest && test -f /workspace/${FILE_ENV_DISTRIB}
then
    echo "The env.list and/or the dockertest directory have not been copied, and/or the env-distrib.list has not been generated."  2>&1 | tee -a ${LOG}
    exit 1
else
# check there are 3 env variables in env.list
    if grep -Fq "DOCKER_VERS" ${FILE_ENV} && grep -Fq "CONTAINERD_VERS" ${FILE_ENV} && grep -Fq "PACKAGING_REF" ${FILE_ENV}
    then
        echo "DOCKER_VERS, CONTAINERD_VERS, PACKAGING_REF are in env.list" 2>&1 | tee -a ${LOG}
    else
        echo "DOCKER_VERS, CONTAINERD_VERS and/or PACKAGING_REF are not in env.list" 2>&1 | tee -a ${LOG}
        exit 1
    fi
# check there are two env variables in env-distrib.list
    if grep -Fq "DEBS" ${FILE_ENV_DISTRIB} && grep -Fq "RPMS" ${FILE_ENV_DISTRIB}
    then
        echo "DEBS and RPMS are in env-distrib.list" 2>&1 | tee -a ${LOG}
    else
        echo "DEBS and/or RPMS are not in env-distrib.list" 2>&1 | tee -a ${LOG}
        exit 1
    fi
fi

if [[ ${CONTAINERD_VERS} = "0" ]]
then
    if test -d /workspace/containerd-*
    then
        echo "The containerd packages have been copied." 2>&1 | tee -a ${LOG}
    else
        echo "The containerd packages have not been copied." 2>&1 | tee -a ${LOG}
        exit 1
    fi
else
    echo "The env.list and the dockertest directory have been copied and the env-distrib.list has been generated." 2>&1 | tee -a ${LOG}
fi
