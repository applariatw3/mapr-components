#!/bin/sh
ACCOUNT=${1:-applariat}
IMAGE_NAME=${2:-mapr-node}
IMAGE_TAG=${3:-6.0.0_4.0.0}
TAG_LATEST=${4:-0}
PUSH_TO_HUB=${5:-0}

shift 5

docker build --no-cache --force-rm  --build-arg MAPR_BUILD="$*" -t $ACCOUNT/$IMAGE_NAME:$IMAGE_TAG .
#docker build --force-rm  --build-arg MAPR_BUILD="$*" -t $ACCOUNT/$IMAGE_NAME:$IMAGE_TAG .

[ $? -ne 0 ] && echo "Problem building the image" && exit 1

[ $TAG_LATEST -eq 1 ] && docker tag $ACCOUNT/$IMAGE_NAME:$IMAGE_TAG $ACCOUNT/$IMAGE_NAME:latest

if [ $PUSH_TO_HUB -eq 1 ]; then
    docker push $ACCOUNT/$IMAGE_NAME:$IMAGE_TAG
    [ $TAG_LATEST -eq 1 ] && docker push $ACCOUNT/$IMAGE_NAME:latest
fi

[ $? -eq 0 ] && echo "Docker Image $ACCOUNT/$IMAGE_NAME:$IMAGE_TAG built"

exit