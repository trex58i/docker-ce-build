#!/bin/bash
# Script building the static docker binaries in a docker container

set -u

set -o allexport
source env.list

${PATH_SCRIPTS}/dockerctl.sh start

DIR_LOGS="/workspace/logs"
STATIC_LOG="static.log"


# Get the latest version of runc
if [[ ! -z ${RUNC_VERS} ]]
then
  echo "~ Get the latest version of runc ~"
  RUNC_VERS=$(eval "git ls-remote --refs --tags https://github.com/opencontainers/runc.git | cut --delimiter='/' --fields=3 | sort --version-sort | tail --lines=1")
  echo "RUNC_VERS = ${RUNC_VERS}"
fi

echo "~~ Building static binaries ~~"
pushd docker-ce-packaging/static

echo "      make static-linux"
echo "           DOCKER_VERS   : ${DOCKER_VERS}"
echo "           CONTAINERD_VER: ${CONTAINERD_VERS}"
echo "           RUNC_VERS     : ${RUNC_VERS}"
VERSION=${DOCKER_VERS} CONTAINERD_VERSION=${CONTAINERD_VERS} RUNC_VERSION=${RUNC_VERS} make static-linux > ${DIR_LOGS}/${STATIC_LOG} 2>&1
echo "      make static-linux : RC: $?"

mkdir build/linux/tmp
if [[ $? -ne 0 ]]
then
  echo "ERROR: Static binaries not built ('make static-linux' failed and build/linux has not been created)"
  exit 1
fi

echo "~~~ Renaming the static binaries ~~~"
# Copy the packages in a tmp directory
cp build/linux/*.tgz build/linux/tmp
popd

# Rename the static binaries (replace the version with ppc64le)
pushd docker-ce-packaging/static/build/linux/tmp
FILES="*"
# There is a mismatch between a version begining with "v" and files version not starting with "v". Don't know why...
DOCKER_VERS_WITHOUT_V=`echo $DOCKER_VERS | sed "s/^v//"`
for f in $FILES
do
  mv $f "${f//${DOCKER_VERS_WITHOUT_V}/ppc64le}"
done
popd

# Check if the binaries have been built and renamed
ls docker-ce-packaging/static/build/linux/tmp/*.tgz
if [[ $? -ne 0 ]]
then
  # No static binaries built
  echo "ERROR: Static binaries not built or not renamed"
  exit 1
else
  # Static binaries built
  ls docker-ce-packaging/static/build/linux/tmp/docker*ppc64le.tgz
  if [[ $? -ne 0 ]]
  then
    # Static binaries built but not renamed
    echo "ERROR: Static binaries built but not renamed"
    exit 1
  fi
  # Static binaries built and renamed
  echo "Static binaries built and renamed"
  exit 0
fi
