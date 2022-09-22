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
echo "           DOCKER_REF    : ${DOCKER_REF}"
echo "           CONTAINERD_REF: ${CONTAINERD_REF}"
echo "           RUNC_VERS     : ${RUNC_VERS}"
echo "           GO_VERSION    : ${GO_VERSION}"
}"
DEBUG="-d"
echo "           DEBUG         : ${DEBUG}"

##
# Patch GO image so that we use bullseye instead of buster which is EOL
##
echo "Patching GO image from buster to bullseye for Makefile"
sed -ri  's/GO_VERSION\)\-buster/GO_VERSION\)\-bullseye/' Makefile

# Launch the build:
VERSION=${DOCKER_REF} CONTAINERD_VERSION=${CONTAINERD_REF} RUNC_VERSION=${RUNC_VERS} make ${DEBUG} static-linux > ${DIR_LOGS}/${STATIC_LOG} 2>&1
RC=$?

if [[ $RC -ne 0 ]]
then
  echo "      make static-linux  : RC: $RC"
  echo "ERROR: Static binaries not built ('make static-linux' failed and build/linux has not been created)"
  exit 1
fi

mkdir build/linux/tmp

echo "~~~ Renaming the static binaries ~~~"
# Copy the packages in a tmp directory
cp build/linux/*.tgz build/linux/tmp
popd

# Rename the static binaries (replace the version with ppc64le)
pushd docker-ce-packaging/static/build/linux/tmp
FILES="*"
# A "tag" is identical to the version, plus a "v" at first.
DOCKER_VERSION=`echo $DOCKER_REF | sed "s/^v//"`
for f in $FILES
do
  mv $f "${f//${DOCKER_VERSION}/ppc64le}"
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
