#!/bin/sh

#Read in the command line options, or use default values
CORE_VERSION=${1:-6.0.0}
MEP_VERSION=${2:-4.0.0}
BASE_OS=${3:-ubuntu14}
ACCOUNT=${4:-maprtech}
IMAGE_NAME=${5:-mapr-core}
IMAGE_TAG=${6:-${CORE_VERSION}_${MEP_VERSION}_${BASE_OS}}
PUSH_TO_HUB=${7:-0}

cp -r Dockerfile.$BASE_OS Dockerfile

docker build --build-arg CORE_VERSION=${CORE_VERSION} --build-arg MEP_VERSION=${MEP_VERSION} --force-rm --pull -t $ACCOUNT/$IMAGE_NAME:$IMAGE_TAG .

[ $? -ne 0 ] && echo "Problem building the image" && exit 1

rm -f Dockerfile

[ $PUSH_TO_HUB -eq 1 ] && docker push $ACCOUNT/$IMAGE_NAME:$IMAGE_TAG

[ $? -eq 0 ] && echo "Docker Image $ACCOUNT/$IMAGE_NAME:$IMAGE_TAG built"

exit
