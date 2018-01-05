#!/bin/sh

# The environment variables in this file are for example only. These variables
# must be altered to match your docker container deployment needs

RUN_IMAGE=${1:-applariat/mapr-edge:6.0.0_4.0.0}
CMD=${2:-/bin/bash}
echo "Starting image $RUN_IMAGE"

shift 1

MAPR_CLUSTER=demo-cluster
MAPR_CLDB_HOSTS=mapr-cldb
MAPR_ZK_HOSTS=mapr-zk
MAPR_ADMIN=mapr
MAPR_ADMIN_PASSWORD=mapr522301
MAPR_MOUNT_PATH=/mapr
MAPR_HS_HOST=
MAPR_RM_HOSTS=
CHECK_CLUSTER=0
MAPR_MCS=mapr-cldb
START_SSH=0
START_WARDEN=0
START_ZK=0
START_FUSE=1

# Container memory: specify host XX[kmg] or 0 for no limit. Ex: 8192m, 12g
MAPR_MEMORY=0

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
  -e MAPR_CLUSTER=$MAPR_CLUSTER \
  -e MAPR_MEMORY=$MAPR_MEMORY \
  -e MAPR_MOUNT_PATH=$MAPR_MOUNT_PATH \
  -e MAPR_ADMIN=$MAPR_ADMIN \
  -e MAPR_ADMIN_PASSWORD=$MAPR_ADMIN_PASSWORD \
  -e MAPR_CLDB_HOSTS=$MAPR_CLDB_HOSTS \
  -e MAPR_HS_HOST=$MAPR_HS_HOST \
  -e MAPR_RM_HOSTS=$MAPR_RM_HOSTS \
  -e MAPR_ZK_HOSTS=$MAPR_ZK_HOSTS \
  -e CHECK_CLUSTER=$CHECK_CLUSTER \
  -e MAPR_MCS=$MAPR_MCS \
  -e START_SSH=$START_SSH \
  -e START_WARDEN=$START_WARDEN \
  -e START_ZK=$START_ZK \
  -e START_FUSE=$START_FUSE \
  $MAPR_DOCKER_ARGS"

[ -f "$MAPR_TICKET_FILE" ] && MAPR_DOCKER_ARGS="$MAPR_DOCKER_ARGS \
  -e MAPR_TICKETFILE_LOCATION=$MAPR_TICKETFILE_LOCATION \
  -v $MAPR_TICKET_FILE:$MAPR_TICKETFILE_LOCATION:ro"

[ $CMD = "/bin/bash" ] && echo "Run '/opt/mapr/docker/start-mapr.sh &' manually to start services after container starts"
docker run --rm -it --name mapr-node $MAPR_DOCKER_ARGS $RUN_IMAGE $CMD
