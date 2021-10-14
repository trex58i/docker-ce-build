#!/bin/bash
# Script building the static docker packages
# in the directory docker-ce-v20.10.9 where there is a static directory with the script
# docker run -d -v /home/fpascual/testing-prow-job:/workspace --privileged --name docker-build-static quay.io/powercloud/docker-ce-build
# docker exec -it docker-build-static /bin/bash
# ./static/build_static.sh
# docker run -d -v /home/fpascual/testing-prow-job:/workspace --env PATH_SCRIPTS --privileged --name docker-build-static quay.io/powercloud/docker-ce-build ./docker_ce_build_ppc64/build_static.sh


set -ue

set -o allexport
source env.list

sh ${PATH_SCRIPTS}/dockerd-entrypoint.sh &
source ${PATH_SCRIPTS}/dockerd-waiting.sh

# get the latest version of runc
echo "~ Get the latest version of runc ~" 2>&1 | tee -a ${LOG}
RUNC_VERS=$(eval "git ls-remote --refs --tags https://github.com/opencontainers/runc.git | cut --delimiter='/' --fields=3 | sort --version-sort | tail --lines=1")
echo "RUNC_VERS = ${RUNC_VERS}" 2>&1 | tee -a ${LOG}

echo "~~ Building static binaries ~~" 2>&1 | tee -a ${LOG}
pushd docker-ce-packaging/static
VERSION=${DOCKER_VERS} CONTAINERD_VERSION=${CONTAINERD_VERS} RUNC_VERSION=${RUNC_VERS} make static-linux
mkdir build/linux/tmp
cp build/linux/*.tgz build/linux/tmp
popd

# rename the static builds (remove the version and add ppc64le)
pushd docker-ce-packaging/static/build/linux/tmp
FILES="*"
for f in $FILES
do
  mv $f "${f//${DOCKER_VERS}/ppc64le}"
done
popd

ls docker-ce-packaging/static/build/linux/tmp/*.tgz
if [[ $? -ne 0 ]]
then
  # static packages not built
  echo "Static binaries not built" 2>&1 | tee -a ${LOG}
  exit 1
else
  # static packages built
  echo "Static binaries built" 2>&1 | tee -a ${LOG}
  exit 0
fi