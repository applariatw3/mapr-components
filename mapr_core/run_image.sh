#!/bin/sh

# The environment variables in this file are for example only. These variables
# must be altered to match your docker container deployment needs

MAPR_CLUSTER=my.cluster.com
MAPR_LICENSE_MODULES=DATABASE,HADOOP,STREAMS
MAPR_CLDB_HOSTS=mapr-cldb
MAPR_ZK_HOSTS=mapr-zk
MAPR_HS_HOST=
MAPR_OT_HOSTS=

# MapR cluster admin user / group
MAPR_USER=mapr
MAPR_UID=5000
MAPR_GROUP=mapr
MAPR_GID=5000
MAPR_USER_PASSWORD=mapr522301

# MapR cluster security: [disabled|enabled|master]
MAPR_SECURITY=disabled

# Container memory: specify host XX[kmg] or 0 for no limit. Ex: 8192m, 12g
MAPR_MEMORY=0

# Container timezone: filename from /usr/share/zoneinfo
#MAPR_TZ=${TZ:-"America/Vancouver"}

# Container network mode: "host" causes the container's sshd service to conflict
# with the host's sshd port (22) and so it will not be enabled in that case
MAPR_DOCKER_NETWORK=bridge

# Container security: --privileged or --cap-add SYS_ADMIN /dev/<device>
#MAPR_DOCKER_SECURITY="--privileged --device $MAPR_DISKS"
MAPR_DOCKER_SECURITY="--privileged"

# Other Docker run args:
MAPR_DOCKER_ARGS="--ipc=host"

### do not edit below this line ###
grep -q -s DISTRIB_ID=Ubuntu /etc/lsb-release && \
  MAPR_DOCKER_SECURITY="$MAPR_DOCKER_SECURITY --security-opt apparmor:unconfined"

MAPR_DOCKER_ARGS="$MAPR_DOCKER_SECURITY \
  --memory $MAPR_MEMORY \
  --network=$MAPR_DOCKER_NETWORK \
  -e MAPR_DISKS=$MAPR_DISKS \
  -e MAPR_CLUSTER=$MAPR_CLUSTER \
  -e MAPR_LICENSE_MODULES=$MAPR_LICENSE_MODULES \
  -e MAPR_MEMORY=$MAPR_MEMORY \
  -e MAPR_MOUNT_PATH=$MAPR_MOUNT_PATH \
  -e MAPR_SECURITY=$MAPR_SECURITY \
  -e MAPR_TZ=$MAPR_TZ \
  -e MAPR_USER=$MAPR_USER \
  -e MAPR_CONTAINER_USER=$MAPR_CONTAINER_USER \
  -e MAPR_CONTAINER_UID=$MAPR_CONTAINER_UID \
  -e MAPR_CONTAINER_GROUP=$MAPR_CONTAINER_GROUP \
  -e MAPR_CONTAINER_GID=$MAPR_CONTAINER_GID \
  -e MAPR_CONTAINER_PASSWORD=$MAPR_CONTAINER_PASSWORD \
  -e MAPR_CLDB_HOSTS=$MAPR_CLDB_HOSTS \
  -e MAPR_HS_HOST=$MAPR_HS_HOST \
  -e MAPR_OT_HOSTS=$MAPR_OT_HOSTS \
  -e MAPR_ZK_HOSTS=$MAPR_ZK_HOSTS \
  -e BUILD_TEST=1 \
  $MAPR_DOCKER_ARGS"

[ -f "$MAPR_TICKET_FILE" ] && MAPR_DOCKER_ARGS="$MAPR_DOCKER_ARGS \
  -e MAPR_TICKETFILE_LOCATION=$MAPR_TICKETFILE_LOCATION \
  -v $MAPR_TICKET_FILE:$MAPR_TICKETFILE_LOCATION:ro"
MAPR_DOCKER_ARGS="$MAPR_DOCKER_ARGS -v $PWD/files:/files"

docker run --rm -it -h mapr-base --name maprb $MAPR_DOCKER_ARGS applariat/mapr-core:6.0.0_4.0.0 /bin/bash "$@"
