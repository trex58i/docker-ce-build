#!/bin/bash
# Script building the static docker binaries in a docker container

set -ue

set -o allexport
source env.list

source ${PATH_SCRIPTS}/dockerd-starting.sh

# Get the latest version of runc
echo "~ Get the latest version of runc ~" 2>&1 | tee -a ${LOG}
RUNC_VERS=$(eval "git ls-remote --refs --tags https://github.com/opencontainers/runc.git | cut --delimiter='/' --fields=3 | sort --version-sort | tail --lines=1")
echo "RUNC_VERS = ${RUNC_VERS}" 2>&1 | tee -a ${LOG}

echo "~~ Building static binaries ~~" 2>&1 | tee -a ${LOG}
pushd docker-ce-packaging/static
VERSION=${DOCKER_VERS} CONTAINERD_VERSION=${CONTAINERD_VERS} RUNC_VERSION=${RUNC_VERS} make static-linux
mkdir build/linux/tmp

echo "~~~ Renaming the static binaries ~~~" 2>&1 | tee -a ${LOG}
# Copy the packages in a tmp directory
cp build/linux/*.tgz build/linux/tmp
popd

# Rename the static binaries (replace the version with ppc64le)
pushd docker-ce-packaging/static/build/linux/tmp
FILES="*"
for f in $FILES
do
  mv $f "${f//${DOCKER_VERS}/ppc64le}"
done
popd

# Check if the binaries have been built and renamed
ls docker-ce-packaging/static/build/linux/tmp/*.tgz
if [[ $? -ne 0 ]]
then
  # No static binaries built
  echo "Static binaries not built or not renamed" 2>&1 | tee -a ${LOG}
  exit 1
else
  # Static binaries built
  ls docker-ce-packaging/static/build/linux/tmp/docker*ppc64le.tgz
  if [[ $? -ne 0 ]]
  then
    # Static binaries built but not renamed
    echo "Static binaries built but not renamed" 2>&1 | tee -a ${LOG}
    exit 1
  fi
  # Static binaries built and renamed
  echo "Static binaries built and renamed" 2>&1 | tee -a ${LOG}
  exit 0
fi
