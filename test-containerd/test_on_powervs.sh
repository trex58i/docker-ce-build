# /usr/bin/bash

set -ux

CRUN_VERSION=1.3

RUNC_FLAVOR=$1
TEST_RUNTIME=$2

cd /home/containerd_test
cd containerd/
git pull

# To syncronize gotestsum
go mod vendor

# Set test variables
if [ "$RUNC_FLAVOR" == "crun" ] && [ "$TEST_RUNTIME" == "io.containerd.runc.v2" ]; then
	export TEST_FLAG="-no-criu"
elif [ "$RUNC_FLAVOR" == "runc" ]; then
	export TEST_FLAG=""
else
	echo "FAIL: Uncompatible option $RUNC_FLAVOR and $TEST_RUNTIME."; exit 1
fi

echo "==== BEGIN RUNC $RUNC_FLAVOR RUNTIME $TEST_RUNTIME ===="
echo "==== INSTALL ===="
export GOFLAGS="-modcacherw"
script/setup/install-seccomp
if [ "$RUNC_FLAVOR" == "runc" ]; then
	script/setup/install-runc
elif [ "$RUNC_FLAVOR" == "crun" ]; then
	apt update
	apt-get install -y make git gcc build-essential pkgconf libtool \
	  libsystemd-dev libprotobuf-c-dev libcap-dev libseccomp-dev libyajl-dev \
	  go-md2man libtool autoconf python3 automake
	TMPROOT=$(mktemp -d)
	git clone https://github.com/containers/crun "${TMPROOT}"/crun
	pushd "${TMPROOT}"/crun
	git checkout "$CRUN_VERSION"
	./autogen.sh
	./configure
	make
	make install # on /usr/local/
	popd
	# runc must be present on $PATH for integration tests
	pushd /usr/local/bin
	ln -s crun runc
	popd
	rm -fr "${TMPROOT}"
fi

script/setup/install-cni $(grep containernetworking/plugins go.mod | awk '{print $2}')
script/setup/install-critools
script/setup/install-gotestsum
unset GOFLAGS

export GOPROXY="direct"

echo "==== BUILD ===="
export CGO_ENABLED=1
make binaries GO_BUILD_FLAGS="-mod=vendor"
make install
unset CGO_ENABLED

echo "==== TEST ===="
GOTEST='gotestsum --' GOTESTSUM_JUNITFILE="junit_test-simple_$RUNC_FLAVOR-$TEST_RUNTIME.xml" make test
echo "==== ROOT-TEST ===="
GOTEST='gotestsum --' GOTESTSUM_JUNITFILE="junit_test-root_$RUNC_FLAVOR-$TEST_RUNTIME.xml" EXTRA_TESTFLAGS="-test.parallel 1" make root-test

echo "==== INTEGRATION TEST ===="
GOTEST='gotestsum --' GOTESTSUM_JUNITFILE="junit_test-integration1_$RUNC_FLAVOR-$TEST_RUNTIME.xml" make integration $TEST_FLAG TESTFLAGS_RACE=-race
GOTEST='gotestsum --' GOTESTSUM_JUNITFILE="junit_test-integration2_$RUNC_FLAVOR-$TEST_RUNTIME.xml" TESTFLAGS_PARALLEL=1 make integration $TEST_FLAG
GOTEST='gotestsum --' GOTESTSUM_JUNITFILE="junit_test-cri-integration_$RUNC_FLAVOR-$TEST_RUNTIME.xml" CONTAINERD_RUNTIME=$TEST_RUNTIME make cri-integration
echo "==== END $RUNC_FLAVOR RUNTIME $TEST_RUNTIME ===="
