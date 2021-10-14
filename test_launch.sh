#!/bin/bash
# Script that launches tests from the repo https://github.ibm.com/powercloud/dockertest

set -ue

# Start the dockerd and wait for it to start
source ${PATH_SCRIPTS}/dockerd-starting.sh

# Run the docker test suite that consists of 3 tests
echo "= Docker test suite for ${DISTRO_NAME} =" 2>&1 | tee -a ${LOG}
export GOPATH=${WORKSPACE}/test:/go
export GO111MODULE=auto
cd /workspace/test/src/github.ibm.com/powercloud/dockertest
make test WHAT="./tests/${DISTRO_NAME}" GOFLAGS="-v"

echo "== End of the docker test suite ==" 2>&1 | tee -a ${LOG}

exit 0
