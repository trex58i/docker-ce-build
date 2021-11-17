#!/bin/bash
# Script testing the docker-ce and containerd packages and the static binaries

set -ue

set -o allexport
source env.list
source env-distrib.list

DIR_TEST="/workspace/test_docker-ce-${DOCKER_VERS}_containerd-${CONTAINERD_VERS}_${DATE}"
export DIR_TEST

DIR_DOCKER="/workspace/docker-ce-${DOCKER_VERS}_${DATE}"
DIR_CONTAINERD="/workspace/containerd-${CONTAINERD_VERS}_${DATE}"

PATH_DOCKERFILE="${PATH_SCRIPTS}/test"

DIR_COS_BUCKET="/mnt/s3_ppc64le-docker/prow-docker/build-docker-${DOCKER_VERS}_${DATE}"

DIR_TEST_COS="${DIR_COS_BUCKET}/test_docker-ce-${DOCKER_VERS}_containerd-${CONTAINERD_VERS}"

FILE_ERRORS="errors.txt"
PATH_ERRORS="${DIR_TEST}/${FILE_ERRORS}"
PATH_ERRORS_COS="${DIR_TEST_COS}/${FILE_ERRORS}"

# Create the test directory
if ! test -d ${DIR_TEST}
then
  mkdir -p "${DIR_TEST}"
fi

if ! test -d ${DIR_TEST_COS}
then
  mkdir -p "${DIR_TEST_COS}"
fi

# Create the errors.txt file where we will put a summary of the test logs
if ! test -f ${PATH_TEST_ERRORS}
then
  touch ${PATH_TEST_ERRORS}
else
  rm ${PATH_TEST_ERRORS}
  touch ${PATH_TEST_ERRORS}
fi

echo "# Tests of the dynamic packages #"
for PACKTYPE in DEBS RPMS
do
  echo "## Looking for distro type ${PACKTYPE} ##" 2>&1 | tee -a ${LOG}

  for DISTRO in ${!PACKTYPE}
  do
    echo "### Looking for ${DISTRO} ###" 2>&1 | tee -a ${LOG}
    DISTRO_NAME="$(cut -d'-' -f1 <<<"${DISTRO}")"
    DISTRO_VERS="$(cut -d'-' -f2 <<<"${DISTRO}")"

    # Get all environment variables
    IMAGE_NAME="t_docker_${DISTRO_NAME}_${DISTRO_VERS}"
    CONT_NAME="t_docker_run_${DISTRO_NAME}_${DISTRO_VERS}"
    BUILD_LOG="build_${DISTRO_NAME}_${DISTRO_VERS}.log"
    TEST_LOG="test_${DISTRO_NAME}_${DISTRO_VERS}.log"
    TEST_JUNIT="unit-tests-${DISTRO_NAME}-${DISTRO_VERS}.xml"

    export DISTRO_NAME
    export DISTRO_VERS

    # Get in the tmp directory and get the docker-ce and containerd packages and the Dockerfile in it
    if ! test -d tmp
    then
      mkdir tmp
    else
      rm -rf tmp
      mkdir tmp
    fi
    pushd tmp

    echo "### # Copying the packages and the dockerfile for ${DISTRO} # ###" 2>&1 | tee -a ${LOG}
    # Copy the docker-ce packages
    cp ${DIR_DOCKER}/bundles-ce-${DISTRO_NAME}-${DISTRO_VERS}-ppc64*.tar.gz .
    # Copy the containerd packages (we have two different configurations depending on the package type)
    CONTAINERD_VERS_2=$(echo ${CONTAINERD_VERS} | cut -d'v' -f2)
    if [[ ${PACKTYPE} == "DEBS" ]]
    then
      # For the debian packages, we don't want the dbgsym package
      cp ${DIR_CONTAINERD}/${DISTRO_NAME}/${DISTRO_VERS}/ppc64*/containerd.io_${CONTAINERD_VERS_2}*_ppc64*.deb .
    elif [[ ${PACKTYPE} == "RPMS" ]]
    then
      cp ${DIR_CONTAINERD}/${DISTRO_NAME}/${DISTRO_VERS}/ppc64*/containerd.io-${CONTAINERD_VERS_2}*.ppc64*.rpm .
    fi

    # Copy the Dockerfile
    cp ${PATH_DOCKERFILE}-${PACKTYPE}/Dockerfile .

    # Copy the test_launch.sh
    cp ${PATH_SCRIPTS}/test_launch.sh .

    # Check if we have the docker-ce and containerd packages and the Dockerfile and the test_launch.sh
    ls bundles-ce-${DISTRO_NAME}-${DISTRO_VERS}-ppc64le.tar.gz && ls containerd*ppc64*.* && ls Dockerfile && ls test_launch.sh
    if [[ $? -ne 0 ]]
    then
      # The docker-ce packages and/or the containerd packages and/or the Dockerfile is/are missing
      echo "The docker-ce packages and/or the containerd packages and/or the Dockerfile is/are missing" 2>&1 | tee -a ${LOG}
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

      # Copying the build log to the COS bucket
      if test -f ${DIR_TEST}/${BUILD_LOG}
      then
        cp ${DIR_TEST}/${BUILD_LOG} ${DIR_TEST_COS}
      fi

      # Running the tests
      echo "### ### Running the tests from the container: ${CONT_NAME} ### ###" 2>&1 | tee -a ${LOG}
      if [[ ! -z ${DOCKER_SECRET_AUTH+z} ]]
      then
        docker run -d -v /workspace:/workspace -v ${PATH_SCRIPTS}:${PATH_SCRIPTS} --env DOCKER_SECRET_AUTH --env DISTRO_NAME --env DISTRO_VERS --env PATH_SCRIPTS --env DIR_TEST --env LOG --privileged --name ${CONT_NAME} ${IMAGE_NAME}
      else
        docker run -d -v /workspace:/workspace -v ${PATH_SCRIPTS}:${PATH_SCRIPTS} --env DISTRO_NAME --env DISTRO_VERS --env PATH_SCRIPTS --env DIR_TEST --env LOG --privileged --name ${CONT_NAME} ${IMAGE_NAME}
      fi

      status_code="$(docker container wait $CONT_NAME)"
      if [[ ${status_code} -ne 0 ]]; then
        echo "ERROR: The test suite failed for ${DISTRO}. See details from '${TEST_LOG}'" 2>&1 | tee -a ${LOG}
        docker logs $CONT_NAME 2>&1 | tee ${DIR_TEST}/${TEST_LOG}
      else
        docker logs $CONT_NAME 2>&1 | tee ${DIR_TEST}/${TEST_LOG}
        echo "Tests done" 2>&1 | tee -a ${LOG}
      fi

      # Copying the test logs to the COS bucket
      if test -f ${DIR_TEST}/${TEST_LOG}
      then
        cp ${DIR_TEST}/${TEST_LOG} ${DIR_TEST_COS}
      fi

      if test -f ${DIR_TEST}/${TEST_JUNIT}
      then
        cp ${DIR_TEST}/${TEST_JUNIT} ${DIR_TEST_COS}
      fi

      # Stop and remove the docker container
      echo "### ### # Cleanup: ${CONT_NAME} # ### ###"
      docker stop ${CONT_NAME}
      docker rm ${CONT_NAME}
      docker image rm ${IMAGE_NAME}
    fi
    popd
    rm -rf tmp

    # Check the logs and get in the errors.txt a summary of the error logs
    echo "### ### ## Checking the logs ## ### ###" 2>&1 | tee -a ${LOG}
    echo "DISTRO ${DISTRO_NAME} ${DISTRO_VERS}" 2>&1 | tee -a ${PATH_TEST_ERRORS}

    if test -f ${DIR_TEST}/${TEST_LOG} && [[ $(eval "cat ${DIR_TEST}/${TEST_LOG} | grep -c exitCode") == 4 ]]
    then
      echo "Dynamic packages" 2>&1 | tee -a ${PATH_TEST_ERRORS}
      # We get 4 exitCodes in the log (3 tests + the output of the first containing exitCode)
      TEST_1=$(eval "cat ${DIR_TEST}/${TEST_LOG} | grep exitCode | awk 'NR==2' | rev | cut -d' ' -f 1")
      TEST_2=$(eval "cat ${DIR_TEST}/${TEST_LOG} | grep exitCode | awk 'NR==3' | rev | cut -d' ' -f 1")
      TEST_3=$(eval "cat ${DIR_TEST}/${TEST_LOG} | grep exitCode | awk 'NR==4' | rev | cut -d' ' -f 1")
    else
      TEST_1=1
      TEST_2=1
      TEST_3=1
    fi

    echo "TestDistro : ${TEST_1}" 2>&1 | tee -a ${PATH_TEST_ERRORS}
    echo "TestDistroInstallPackage : ${TEST_2}" 2>&1 | tee -a ${PATH_TEST_ERRORS}
    echo "TestDistroPackageCheck : ${TEST_3}" 2>&1 | tee -a ${PATH_TEST_ERRORS}

    [[ "$TEST_1" -eq "0" ]] && [[ "$TEST_2" -eq "0" ]] && [[ "$TEST_3" -eq "0" ]]
    TEST=$?

    # Copying the errors.txt to the COS bucket
    cp ${PATH_ERRORS} ${PATH_ERRORS_COS}
  done
done

echo "# Tests for the static packages #" 2>&1 | tee -a ${LOG}

DISTRO_NAME="alpine"

IMAGE_NAME_STATIC="t-static_docker_${DISTRO_NAME}"
CONT_NAME_STATIC="t-static_docker_run_${DISTRO_NAME}"
BUILD_LOG_STATIC="build-static_${DISTRO_NAME}.log"
TEST_LOG_STATIC="test-static_${DISTRO_NAME}.log"
TEST_JUNIT_STATIC="unit-tests-${DISTRO_NAME}.xml"

export DISTRO_NAME

# Get in the tmp directory and get the docker-ce and containerd packages and the Dockerfile in it
if ! test -d tmp
then
  mkdir tmp
else
  rm -rf tmp
  mkdir tmp
fi
pushd tmp

echo "## Copying the static packages and the dockerfile for ${DISTRO} ##" 2>&1 | tee -a ${LOG}
# Copy the static binaries
cp ${DIR_DOCKER}/docker-ppc64le.tgz .
# Copy the Dockerfile
cp ${PATH_DOCKERFILE}-static-alpine/Dockerfile .
# Copy the test_launch.sh
cp ${PATH_SCRIPTS}/test_launch.sh .
# Check if we have the static binaries and Dockerfile and the test_launch.sh
ls docker-ppc64le.tgz && ls Dockerfile && ls test_launch.sh
if [[ $? -ne 0 ]]
then
  # The static binaries and/or the Dockerfile is/are missing
  echo "The static binaries and/or the Dockerfile and/or the test_launch.sh is/are missing" 2>&1 | tee -a ${LOG}
  continue
else
  # Building the test image
  echo "### # Building the test image: ${IMAGE_NAME_STATIC} # ###" 2>&1 | tee -a ${LOG}
  docker build -t ${IMAGE_NAME_STATIC} . 2>&1 | tee ${DIR_TEST}/${BUILD_LOG_STATIC}

  if [[ $? -ne 0 ]]; then
    echo "ERROR: docker build failed for ${DISTRO_NAME}, see details from '${BUILD_LOG_STATIC}'" 2>&1 | tee -a ${LOG}
    continue
  else
    echo "Docker build done" 2>&1 | tee -a ${LOG}
  fi

  # Copying the build log to the COS bucket
  if test -f ${DIR_TEST}/${BUILD_LOG_STATIC}
  then
    cp ${DIR_TEST}/${BUILD_LOG_STATIC} ${DIR_TEST_COS}
  fi

  # Running the tests
  echo "### ## Running the tests from the container: ${CONT_NAME_STATIC} ## ###" 2>&1 | tee -a ${LOG}
  if [[ ! -z ${DOCKER_SECRET_AUTH+z} ]]
  then
    docker run --env DOCKER_SECRET_AUTH --env DISTRO_NAME --env PATH_SCRIPTS --env DIR_TEST --env LOG -d -v /workspace:/workspace -v ${PATH_SCRIPTS}:${PATH_SCRIPTS} --privileged --name ${CONT_NAME_STATIC} ${IMAGE_NAME_STATIC}
  else
    docker run --env DISTRO_NAME --env PATH_SCRIPTS --env DIR_TEST --env LOG -d -v /workspace:/workspace -v ${PATH_SCRIPTS}:${PATH_SCRIPTS} --privileged --name ${CONT_NAME_STATIC} ${IMAGE_NAME_STATIC}
  fi

  status_code="$(docker container wait ${CONT_NAME_STATIC})"
  if [[ ${status_code} -ne 0 ]]; then
    echo "ERROR: The test suite failed for ${DISTRO}. See details from '${TEST_LOG_STATIC}'" 2>&1 | tee -a ${LOG}
    docker logs ${CONT_NAME_STATIC} 2>&1 | tee ${DIR_TEST}/${TEST_LOG_STATIC}
  else
    docker logs ${CONT_NAME_STATIC} 2>&1 | tee ${DIR_TEST}/${TEST_LOG_STATIC}
    echo "Tests done" 2>&1 | tee -a ${LOG}
  fi

  # Copying the test logs to the COS bucket
  if test -f ${DIR_TEST}/${TEST_LOG_STATIC}
  then
    cp ${DIR_TEST}/${TEST_LOG_STATIC} ${DIR_TEST_COS}
  fi

  if test -f ${DIR_TEST}/${TEST_JUNIT_STATIC}
  then
    cp ${DIR_TEST}/${TEST_JUNIT_STATIC} ${DIR_TEST_COS}
  fi

  # Stop and remove the docker container
  echo "### ### # Cleanup: ${CONT_NAME_STATIC} # ### ###" 2>&1 | tee -a ${LOG}
  docker stop ${CONT_NAME_STATIC}
  docker rm ${CONT_NAME_STATIC}
  docker image rm ${IMAGE_NAME_STATIC}
fi
popd
rm -rf tmp

if test -f ${DIR_TEST}/${TEST_LOG_STATIC} && [[ $(eval "cat ${DIR_TEST}/${TEST_LOG_STATIC} | grep -c exitCode") == 4 ]]
then
  echo "Static binaries" 2>&1 | tee -a ${PATH_TEST_ERRORS}
  # We get 4 exitCodes in the log (3 tests + the output of the first containing exitCode)
  TEST_1_STATIC=$(eval "cat ${DIR_TEST}/${TEST_LOG_STATIC} | grep exitCode | awk 'NR==2' | rev | cut -d' ' -f 1")
  TEST_2_STATIC=$(eval "cat ${DIR_TEST}/${TEST_LOG_STATIC} | grep exitCode | awk 'NR==3' | rev | cut -d' ' -f 1")
  TEST_3_STATIC=$(eval "cat ${DIR_TEST}/${TEST_LOG_STATIC} | grep exitCode | awk 'NR==4' | rev | cut -d' ' -f 1")
else
  TEST_1_STATIC=1
  TEST_2_STATIC=1
  TEST_3_STATIC=1
fi

echo "TestDistro : ${TEST_1_STATIC}" 2>&1 | tee -a ${PATH_TEST_ERRORS}
echo "TestDistroInstallPackage : ${TEST_2_STATIC}" 2>&1 | tee -a ${PATH_TEST_ERRORS}
echo "TestDistroPackageCheck : ${TEST_3_STATIC}" 2>&1 | tee -a ${PATH_TEST_ERRORS}

[[ "$TEST_1_STATIC" -eq "0" ]] && [[ "$TEST_2_STATIC" -eq "0" ]] && [[ "$TEST_3_STATIC" -eq "0" ]]
TEST_STATIC=$?

[[ "$TEST" -eq "0" ]] && [[ "$TEST_STATIC" -eq "0" ]]
echo "All : $?" 2>&1 | tee -a ${PATH_TEST_ERRORS}
tail -9 ${PATH_TEST_ERRORS} 2>&1 | tee -a ${LOG}

# Copying the errors.txt to the COS bucket
cp ${PATH_ERRORS} ${PATH_ERRORS_COS}
