#/bin/bash

##
# docker run -d -v /home/fpascual:/workspace -v /home/fpascual/.docker/config.json:/root/.docker/config.json --privileged --name docker-test-staging quay.io/powercloud/docker-ce-build
# docker exec -it docker-test-staging /bin/bash
##
#set -eux

set -ue

set -o allexport
source env.list
source env-distrib.list

DIR_TEST="/workspace/test-staging_docker-ce-${DOCKER_VERS}_containerd-${CONTAINERD_VERS}"
PATH_DOCKERFILE="${PATH_SCRIPTS}/test-staging"
PATH_TEST_ERRORS="${DIR_TEST}/errors.txt"

# Create the test directory
if ! test -d ${DIR_TEST}
then
    mkdir -p "${DIR_TEST}"
fi

# Create the errors.txt file where we will put a summary of the test logs
if ! test -f ${PATH_TEST_ERRORS}
then
    touch ${PATH_TEST_ERRORS}
else
    rm ${PATH_TEST_ERRORS}
    touch ${PATH_TEST_ERRORS}
fi

for PACKTYPE in DEBS RPMS
do
    echo "# Looking for distro type: ${PACKTYPE} #" 2>&1 | tee -a ${LOG}

    for DISTRO in ${!PACKTYPE}
    do
        echo "## Looking for ${DISTRO} ##" 2>&1 | tee -a ${LOG}
        DISTRO_NAME="$(cut -d'-' -f1 <<<"${DISTRO}")"
        DISTRO_VERS="$(cut -d'-' -f2 <<<"${DISTRO}")"

	# Get all environment variables
        IMAGE_NAME="t_docker_${DISTRO_NAME}_${DISTRO_VERS}"
        CONT_NAME="t_docker_run_${DISTRO_NAME}_${DISTRO_VERS}"
        BUILD_LOG="build_${DISTRO_NAME}_${DISTRO_VERS}.log"
        TEST_LOG="test_${DISTRO_NAME}_${DISTRO_VERS}.log"

        export DISTRO_NAME

        echo "### Tests for docker-ce and containerd packages ###" 2>&1 | tee -a ${LOG}
        # Get in the tmp directory and get the Dockerfile
        if ! test -d tmp
        then
            mkdir tmp
        else
            rm -rf tmp
            mkdir tmp
        fi

        pushd tmp
        echo "### # Copying the packages and the dockerfile for ${DISTRO} # ###" 2>&1 | tee -a ${LOG}
        # Copy the Dockerfile
        cp ${PATH_DOCKERFILE}-${PACKTYPE}/Dockerfile .
        # Copy the test_launch.sh which will be copied in /usr/local/bin
        cp ${PATH_SCRIPTS}/test_launch.sh .

	# Check if we have the Dockerfile and the test_launch.sh
	ls Dockerfile && ls test_launch.sh
	if [[ $? -ne 0 ]]
	then
	    # The Dockerfile and/or the test_launch.sh is/are missing
	    echo "The Dockerfile and/or the test_launch.sh is/are missing." 2>&1 | tee -a ${LOG}
	    continue
	else
	    # Building the test image
            echo "### ## Building the test image: ${IMAGE_NAME} ## ###" 2>&1 | tee -a ${LOG}
            docker build -t ${IMAGE_NAME} --build-arg DISTRO_NAME=${DISTRO_NAME} --build-arg DISTRO_VERS=${DISTRO_VERS} . 2>&1 | tee ${DIR_TEST}/${BUILD_LOG}

            if [[ $? -ne 0 ]]; then
                echo "ERROR: docker build failed for ${DISTRO}, see details from '${BUILD_LOG}'" 2>&1 | tee -a ${LOG}
                continue
            else
                echo "Docker build for ${DISTRO} done" 2>&1 | tee -a ${LOG}
            fi

            echo "### ### Running the tests from the container: ${CONT_NAME} ### ###" 2>&1 | tee -a ${LOG}
            docker run --env DOCKER_SECRET_AUTH --env DISTRO_NAME --env PATH_SCRIPTS --env LOG -d -v /workspace:/workspace -v ${PATH_SCRIPTS}:${PATH_SCRIPTS} --privileged --name $CONT_NAME ${IMAGE_NAME}

	    status_code="$(docker container wait $CONT_NAME)"
            if [[ ${status_code} -ne 0 ]]; then
                echo "ERROR: The test suite failed for ${DISTRO}. See details from '${TEST_LOG}'" 2>&1 | tee -a ${LOG}
                docker logs $CONT_NAME 2>&1 | tee ${DIR_TEST}/${TEST_LOG}
            else
                docker logs $CONT_NAME 2>&1 | tee ${DIR_TEST}/${TEST_LOG}
                echo "Tests done" 2>&1 | tee -a ${LOG}
            fi

            echo "### ### # Cleanup: ${CONT_NAME} # ### ###"
            docker stop ${CONT_NAME}
            docker rm ${CONT_NAME}
            docker image rm ${IMAGE_NAME}
	fi
	popd
        rm -rf tmp

	# Check the logs and get in the errors.txt a summary of the error logs
        if test -f ${DIR_TEST}/${TEST_LOG}
        then
            echo "### # Checking the logs # ###"
            echo "DISTRO ${DISTRO_NAME} ${DISTRO_VERS}" 2>&1 | tee -a ${PATH_TEST_ERRORS}
            TEST_1=$(eval "cat ${DIR_TEST}/${TEST_LOG} | grep exitCode | awk 'NR==2' | rev | cut -d' ' -f 1")
            echo "TestDistro : ${TEST_1}" 2>&1 | tee -a ${PATH_TEST_ERRORS}

            TEST_2=$(eval "cat ${DIR_TEST}/${TEST_LOG} | grep exitCode | awk 'NR==3' | rev | cut -d' ' -f 1")
            echo "TestDistroInstallPackage : ${TEST_2}" 2>&1 | tee -a ${PATH_TEST_ERRORS}

            TEST_3=$(eval "cat ${DIR_TEST}/${TEST_LOG} | grep exitCode | awk 'NR==4' | rev | cut -d' ' -f 1")
            echo "TestDistroPackageCheck : ${TEST_3}" 2>&1 | tee -a ${PATH_TEST_ERRORS}

            [[ "$TEST_1" -eq "0" ]] && [[ "$TEST_2" -eq "0" ]] && [[ "$TEST_3" -eq "0" ]]
            echo "All : $?" 2>&1 | tee -a ${PATH_TEST_ERRORS}
            tail -5 ${PATH_TEST_ERRORS}
        else
            echo "There is no ${TEST_LOG} file." 2>&1 | tee -a ${LOG}
        fi
    done
done
