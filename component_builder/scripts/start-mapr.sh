#!/bin/bash
#Start the mapr services in the container and then tail the appropriate log to stdout
#This script is called as the command for the container and replaces supervisord
MAPR_CONTAINER_DIR=${MAPR_CONTAINER_DIR:-/opt/mapr/docker}

source $MAPR_CONTAINER_DIR/start-env.sh
#source ./start-env.sh

#Should be set in start-env.sh
MAPR_CORE=${MAPR_CORE:-1}
MAPR_CLIENT=${MAPR_CLIENT:-0}
START_SSH=${START_SSH:-1}
START_NFS=${START_NFS:-0}
START_ZK=${START_ZK:-0}
START_WARDEN=${START_WARDEN:-0}
START_FUSE=${START_FUSE:-0}
MAPR_ADMIN=${MAPR_ADMIN:-mapr}
MAPR_ADMIN_GROUP=${MAPR_ADMIN_GROUP:-mapr}
MAPR_ADMIN_PASS=${MAPR_ADMIN_PASS:-mapr522301}
CLUSTER_NAME=${CLUSTER_NAME:-demo-cluster}
MCS_HOST=${MCS_HOST:-mapr-cldb}
CHECK_CLUSTER=${CHECK_CLUSTER:-1}
MCS_PORT=${MCS_PORT:-8443}
MAPR_MOUNT_PATH=${MAPR_MOUNT_PATH:-/mapr}
CLUSTER_INFO_DIR=${CLUSTER_INFO_DIR:-/user/mapr/$CLUSTER_NAME}


#Script Variables
LOG_TO_TAIL=null
SSHD_PID_FILE=/var/run/sshd.pid
ZK_PID_FILE=$MAPR_HOME/zkdata/zookeeper_server.pid
WARDEN_PID_FILE=/opt/mapr/pid/warden.pid
MCS_URL="https://${MCS_HOST}:${MCS_PORT}"
MAPR_FUSE_FILE="$MAPR_HOME/conf/fuse.conf"
SSHD=ssh
[ "$OS" = "centos" ] && SSHD=sshd

chk_str="Waiting"
check_cluster(){
	if ! $(curl --output /dev/null -Iskf $MCS_URL); then
		chk_str="Waiting for MCS at $MCS_URL to start..."
		return 1
	fi

	find_cldb="curl -sSk -u ${MAPR_ADMIN}:${MAPR_ADMIN_PASS} ${MCS_URL}/rest/node/cldbmaster"
	if [ "$($find_cldb | jq -r '.status')" = "OK" ]; then
		return 0
	else
		echo "Connected to $MCS_URL, Waiting for CLDB Master to be Ready..."
		return 1
	fi
}

echo "Starting Support Services"
[ $START_SSH -eq 1 ] && service $SSHD start

if [ "$OS" = "centos" ]; then
	[ $START_NFS -eq 1 ] && service rpcbind start && service nfs-lock start
fi

#Main
echo "Starting MAPR Services"
while /bin/true; do
	
    if [ $START_ZK -eq 1 ]; then
    	ver=$(cat ${MAPR_HOME}/zookeeper/zookeeperversion)
    	ZK_LOG="${MAPR_HOME}/zookeeper/zookeeper-${ver}/logs/zookeeper.log"
    	
    	service mapr-zookeeper start
    	
    	LOG_TO_TAIL=zookeeper
	fi
	
	if [ $START_WARDEN -eq 1 ]; then
		WARDEN_LOG="${MAPR_HOME}/logs/warden.log"
	
		if [ $START_ZK -eq 0 ]; then
			service mapr-warden start
			LOG_TO_TAIL=warden
		else
			service mapr-warden start
		fi
		
		sleep 5

		if [ -f ${MAPR_HOME}/roles/fileserver ]; then
		
			#Add location on MAPR-FS to store cluster info
			if $(hadoop fs -test -d $CLUSTER_INFO_DIR); then
				echo "$CLUSTER_INFO_DIR directory exists in MAPR-FS"
			else
				echo "Creating $CLUSTER_INFO_DIR on MAPR-FS"
				hadoop fs -mkdir -p $CLUSTER_INFO_DIR
				hadoop fs -chown -R $MAPR_ADMIN:$MAPR_GROUP $CLUSTER_INFO_DIR
				hadoop fs -chmod -R 755 $CLUSTER_INFO_DIR
			fi
		
			#If a cldb node, push some info to cluster info
			#if [ ! -f $MAPR_HOME/roles/cldb ]; then
			#	echo "Writing cluster config information to $CLUSTER_INFO_DIR/"
		
			#	maprcli license showid -json |jq -r '.data[].id' >> /tmp/mapr-cluster-id

			
			#	hadoop fs -put /tmp/mapr-cluster-id $CLUSTER_INFO_DIR/
			#	hadoop fs -chown mapr:mapr $CLUSTER_INFO_DIR/mapr-cluster-id
			#fi
		fi
	
		#If a Drill Bits node, push some info to cluster info
		if [ -f $MAPR_HOME/roles/drill-bits ]; then
			echo "Writing drill-bits config information to $CLUSTER_INFO_DIR/"
			ver=$(cat $MAPR_HOME/drill/drillversion)
			DRILL_OVR="$MAPR_HOME/drill/drill-${ver}/bin/drill-override.conf"
	
			grep cluster-id $DRILL_OVR | egrep -o '\"[a-z\-]+\"' > /tmp/drill-cluster-id
		
			hadoop fs -put /tmp/drill-cluster-id $CLUSTER_INFO_DIR/
			hadoop fs -chown mapr:mapr $CLUSTER_INFO_DIR/drill-cluster-id
		fi
	
		#If a Spark Master node, Configure Spark
		if [ -f $MAPR_HOME/roles/spark-master ]; then
			echo "Configuring Spark Master Node"
		
			if $(hadoop fs -test -d /apps/spark); then
				echo "Spark directory exists"
			else
				echo "Creating Spark Directory"
				hadoop fs -mkdir -p /apps/spark
				hadoop fs -chown -R $MAPR_ADMIN:$MAPR_GROUP /apps/spark
				hadoop fs -chmod -R 777 /apps/spark
			fi
		fi

		#If a Spark Yarn node, Configure Spark
		if [ -d $MAPR_HOME/spark ]; then
			echo "Configuring Spark on Yarn Node"
	
			if $(hadoop fs -test -d /apps/spark); then
				echo "Spark directory exists"
			else
				echo "Creating Spark Directory"
				hadoop fs -mkdir -p /apps/spark
				hadoop fs -chown -R $MAPR_ADMIN:$MAPR_GROUP /apps/spark
				hadoop fs -chmod 777 /apps/spark
			fi
		fi
	fi
	
	if [ $START_FUSE -eq 1 ]; then
		[ -f /etc/init.d/mapr-posix-client-container ] && svc=mapr-posix-client-container
		[ -f /etc/init.d/mapr-posix-client-basic ] && svc=mapr-posix-client-basic
		[ -f /etc/init.d/mapr-posix-client-platinum ] && svc=mapr-posix-client-platinum
		
		#client install set mapr ownership
		if [ $MAPR_CLIENT -eq 1 ]; then
			chown -R $MAPR_ADMIN:$MAPR_ADMIN_GROUP "$MAPR_HOME"
			chown -fR root:root "$MAPR_HOME/conf/proxy"
		fi
		
		if [ $CHECK_CLUSTER -eq 1 ]; then
			until check_cluster; do
				echo "$chk_str"
				sleep 10
			done
			echo "CLDB Master is ready, continuing startup for $CLUSTER_NAME..."
		fi
		
		if [ -n "$MAPR_MOUNT_PATH" -a -f "$MAPR_FUSE_FILE" ]; then
			echo "Starting Fuse Client with $MAPR_MOUNT_PATH"
			sed -i "s|^fuse.mount.point.*$|fuse.mount.point=$MAPR_MOUNT_PATH|g" \
				$MAPR_FUSE_FILE || echo "Could not set FUSE mount path"
			mkdir -p -m 755 "$MAPR_MOUNT_PATH"
		
			#Make sure fuse is not running
			service $svc stop
			service $svc start
		fi
	fi
	
	sleep 5
	echo "Exporting logs from $LOG_TO_TAIL"
	case $LOG_TO_TAIL in
		warden)
			tail -f $WARDEN_LOG
		    #if [ -f $WARDEN_PID_FILE ]; then
		    #	warden_pid=$(cat $WARDEN_PID_FILE)
			#	ps aux | grep $warden_pid | grep -q -v grep && \
			#	  tail -f --pid $warden_pid $WARDEN_LOG
			#fi
			;;
		zookeeper)
			tail -f $ZK_LOG
			#if [ -f $ZK_PID_FILE ]; then
			#	zk_pid=$(cat $ZK_PID_FILE)
			#	ps aux | grep $zk_pid | grep -q -v grep && \
			#  	  tail -f --pid $zk_pid $ZK_LOG
			#fi
			;;
		null|*)
			tail -f /dev/null
			;;
	esac
done

exit 0

