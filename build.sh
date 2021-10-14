#!/bin/bash
# Script building the docker-ce and containerd packages

set -ue

set -o allexport
source env.list
source env-distrib.list

echo "# Building docker-ce #" 2>&1 | tee -a ${LOG}

DIR_DOCKER="docker-ce-${DOCKER_VERS}"
if ! test -d ${DIR_DOCKER}
then
  mkdir ${DIR_DOCKER}
fi

STATIC_LOG=/workspace/static.log

# Workaround for builkit cache issue where fedora-32/Dockerfile
# (or the 1st Dockerfile used by buildkit) is used for all fedora's version
# See https://github.com/moby/buildkit/issues/1368
patchDockerFiles() {
  Dockfiles="$(find $1  -name 'Dockerfile')"
  d=$(date +%s)
  i=0
  for file in ${Dockfiles}; do
      i=$(( i + 1 ))
      echo "patching timestamp for ${file}"
      touch -d @$(( d + i )) "${file}"
  done
}

pushd docker-ce-packaging/deb
patchDockerFiles .
for DEB in ${DEBS}
do
  echo "= Building for: ${DEB} =" 2>&1 | tee -a ${LOG}

  VERSION=${DOCKER_VERS} make debbuild/bundles-ce-${DEB}-ppc64le.tar.gz

  if test -f debbuild/bundles-ce-${DEB}-ppc64le.tar.gz
  then
    echo "${DEB} built" 2>&1 | tee -a ${LOG}
  else
    echo "${DEB} not built" 2>&1 | tee -a ${LOG}
  fi
done
popd

pushd docker-ce-packaging/rpm
patchDockerFiles .
for RPM in ${RPMS}
do
  echo "== Building for: ${RPM} ==" 2>&1 | tee -a ${LOG}

  VERSION=${DOCKER_VERS} make rpmbuild/bundles-ce-${RPM}-ppc64le.tar.gz

  if test -f rpmbuild/bundles-ce-${RPM}-ppc64le.tar.gz
  then
    echo "${RPM} built" 2>&1 | tee -a ${LOG}
  else
    echo "${RPM} not built" 2>&1 | tee -a ${LOG}
  fi
done
popd

echo "=== Building static ===" 2>&1 | tee -a ${LOG}
pushd docker-ce-packaging/static

CONT_NAME=docker-build-static
docker run -d -v /workspace:/workspace -v /home/prow/go/src/github.com/ppc64le-cloud/docker-ce-build:/home/prow/go/src/github.com/ppc64le-cloud/docker-ce-build --env PATH_SCRIPTS --env LOG --env DOCKER_SECRET_AUTH --privileged --name ${CONT_NAME} quay.io/powercloud/docker-ce-build ${PATH_SCRIPTS}/build_static.sh

status_code="$(docker container wait ${CONT_NAME})"
if [[ ${status_code} -ne 0 ]]; then
  echo "The static binaries build failed. See details from '${STATIC_LOG}'" 2>&1 | tee -a ${LOG}
  docker logs ${CONT_NAME} 2>&1 | tee ${STATIC_LOG}
else
  docker logs ${CONT_NAME} 2>&1 | tee ${STATIC_LOG}
  echo "Static binaries built" 2>&1 | tee -a ${LOG}
fi


popd

echo "==== Copying packages to ${DIR_DOCKER} ====" 2>&1 | tee -a ${LOG}

cp -r docker-ce-packaging/deb/debbuild/*.tar.gz ${DIR_DOCKER}
cp -r docker-ce-packaging/rpm/rpmbuild/*.tar.gz ${DIR_DOCKER}
cp docker-ce-packaging/static/build/linux/tmp/*.tgz ${DIR_DOCKER}

if [[ ${CONTAINERD_VERS} != "0" ]]
# if CONTAINERD_VERS is equal to a version of containerd we want to build
then
  echo "## Building containerd ##" 2>&1 | tee -a ${LOG}

  DIR_CONTAINERD="/workspace/containerd-${CONTAINERD_VERS}"
  mkdir ${DIR_CONTAINERD}

  git clone https://github.com/docker/containerd-packaging.git

  pushd containerd-packaging

  DISTROS="${DEBS//-/:} ${RPMS//-/:}"

  for DISTRO in $DISTROS
  do
    echo "= Building for: ${DISTRO} =" 2>&1 | tee -a ${LOG}
    make REF=${CONTAINERD_VERS} docker.io/library/${DISTRO}
    DISTRO_NAME="$(cut -d':' -f1 <<<"${DISTRO}")"
    DISTRO_VERS="$(cut -d':' -f2 <<<"${DISTRO}")"

    if test -d build/${DISTRO_NAME}/${DISTRO_VERS}
    then
      echo "${DISTRO} built" 2>&1 | tee -a ${LOG}
    else
      echo "${DISTRO} not built" 2>&1 | tee -a ${LOG}
    fi
  done

  popd
  echo "== Copying packages to ${DIR_CONTAINERD} ==" 2>&1 | tee -a ${LOG}
  cp -r containerd-packaging/build/* ${DIR_CONTAINERD}
else
  echo "Change CONTAINERD_VERS from 0 to the last version we got from the COS Bucket" 2>&1 | tee -a ${LOG}
  ls -d /workspace/containerd-*
  if [[ $? -ne 0 ]]
  then
    echo "There is no containerd package." 2>&1 | tee -a ${LOG}
    exit 1
  fi
  CONTAINERD_VERS=$(eval "ls -d /workspace/containerd-* | cut -d'-' -f2")
  echo ${CONTAINER_VERS} 2>&1 | tee -a ${LOG}
  sed -i 's/CONTAINERD_VERS=0/CONTAINERD_VERS='${CONTAINERD_VERS}'/g' env.list
  source env.list
fi

# Check if the docker-ce packages have been built
ls ${DIR_DOCKER}/*
if [[ $? -ne 0 ]]
then
  # No packages built
  echo "No packages built for docker" 2>&1 | tee -a ${LOG}
  BOOL_DOCKER=0
else
  # Packages built
  BOOL_DOCKER=1
fi

# Check if the containerd packages have been built
ls ${DIR_CONTAINERD}/*
if [[ $? -ne 0 ]]
then
  # No packages built
  echo "No packages built for containerd" 2>&1 | tee -a ${LOG}
  BOOL_CONTAINERD=0
else
  # Packages built
  BOOL_CONTAINERD=1
fi

# Check if all packages have been built
if [[ ${BOOL_DOCKER} -eq 0 ]] || [[ ${BOOL_CONTAINERD} -eq 0 ]]
# if there is no packages built for docker or no packages built for containerd
then 
  echo "No packages built for either docker, or containerd" 2>&1 | tee -a ${LOG}
  exit 1
elif [[ ${BOOL_DOCKER} -eq 1 ]] && [[ ${BOOL_CONTAINERD} -eq 1 ]]
# if there are packages built for docker and packages built for containerd
then
  echo "All packages built" 2>&1 | tee -a ${LOG}
fi
