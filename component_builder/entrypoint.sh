#!/bin/bash
#mapr server entrypoint script

echo "Starting MAPR container ${POD_NAME} from entrypoint.sh"

#set environment from inputs
MAPR_CLUSTER=${MAPR_CLUSTER:-my.cluster.com}
MAPR_CLDB_HOSTS=${MAPR_CLDB_HOSTS:$HOST}
MAPR_ZK_HOSTS=${MAPR_ZK_HOSTS:$HOST}
MAPR_RM_HOSTS=$MAPR_RM_HOSTS
MAPR_FS_HOSTS=$MAPR_FS_HOSTS
MAPR_YARN_HOSTS=$MAPR_YARN_HOSTS
MAPR_MRV1_HOSTS=$MAPR_MRV1_HOSTS
MAPR_CLIENT_HOSTS=$MAPR_CLIENT_HOSTS
MAPR_HS_HOST=$MAPR_HS_HOST
MAPR_OT_HOSTS=$MAPR_OT_HOSTS
MAPR_ES_HOSTS=$MAPR_ES_HOSTS
MYSQL_HOST=$MYSQL_HOST
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS:-ChangeMe!}
USE_MAPR_LOGGING=${USE_MAPR_LOGGING:-false}
USE_MAPR_MONITORING=${USE_MAPR_MONITORING:-false}
USE_MAPR_METRICS=${MAPR_METRICS:-false}
MAPR_METRICS_DB=${MAPR_METRICS_DB:-metrics}
MAPR_METRICS_USER=${MYSQL_USER:-metrics}
MAPR_METRICS_PASS=${MYSQL_PASS:-metrics}
HIVE_DB=${HIVE_DB:-hive}
HIVE_USER=${HIVE_USER:-hive}
HIVE_PASS=${HIVE_PASS:-hive}

MAPR_DISKS=${MAPR_DISKS:-/dev/sdb}
MAPR_LICENSE_MODULES=${MAPR_LICENSE_MODULES:-DATABASE,HADOOP,STREAMS}
MAPR_SECURITY=${MAPR_SECURITY:-disabled}
MAPR_MEMORY=${NODE_MEMORY:-8G}
MAPR_SUBNETS=$MAPR_SUBNETS
MAPR_UID=${MAPR_UID:-5000}
MAPR_GID=${MAPR_GID:-5000}
MAPR_ADMIN=${MAPR_ADMIN:-mapr}
MAPR_ADMIN_PASSWORD=${MAPR_ADMIN_PASSWORD:-mapr522301}
MAPR_GROUP=${MAPR_GROUP:-mapr}
USE_FAKE_DISK=${USE_FAKE_DISK:-0}
ADD_SWAP=${ADD_SWAP:-0}
MAPR_DATA_MOUNT=${MAPR_DATA_MOUNT:-/data/mapr}




#Used for APL Notifications
APL_EVENT=0
if [ -n "$APL_API_KEY" ]; then
	APL_EVENT=1
	echo "Configuring to update events in APL"
	APL_API="${APL_API:-https://api.applariat.io/v1}"
	auth="Authorization: ApiKey $APL_API_KEY"
	APL_DEPLOYMENT_ID=$(curl -sS -H "$auth" -X GET $APL_API/deployments?name=$NAMESPACE |jq -r '.data[0].id')
fi

notify_apl() {
	cat > /tmp/apl-event.json << EOC
{"data": {
		"event_type": "update_object",
		"force_save": true,
		"object_type": "deployment",
		"update_data": {
			"status": {
				"state": "deployed",
				"namespace": "$NAMESPACE",
				"description": "$1"
			}
		},
		"object_name": "$APL_DEPLOYMENT_ID",
		"source": "propeller",
		"active": true,
		"message": "$1"
	}
}
EOC

	response=$(curl -sS -H "$auth" -H "Content-Type: application/json" -X POST $APL_API/events --data-binary @/tmp/apl-event.json | jq '.')

	echo "Applariat API response: $response"
}

[ $APL_EVENT -eq 1 ] && notify_apl "Starting configuration of MAPR node: ${POD_NAME}"

#export path
export PATH=$JAVA_HOME/bin:$MAPR_HOME/bin:$PATH
export CLASSPATH=$CLASSPATH

#internal environment
MAPR_ULIMIT_U=64000
MAPR_ULIMIT_N=64000
MAPR_SYSCTL_SOMAXCONN=20000
MAPR_UMASK=022
MAPR_ENV_FILE=/etc/profile.d/mapr.sh
MAPR_LIB_DIR=$MAPR_HOME/lib
MAPR_CLUSTER_CONF="$MAPR_HOME/conf/mapr-clusters.conf"
MAPR_CONFIGURE_SCRIPT="$MAPR_HOME/server/configure.sh"
MAPR_RUN_DISKSETUP=0
MAPR_DISKSETUP="$MAPR_HOME/server/disksetup"
FORCE_FORMAT=1
STRIPE_WIDTH=3
REBUILD_NODE=1

#used for startup
MAPR_START_ENV=${MAPR_CONTAINER_DIR}/start-env.sh
CLUSTER_INFO_DIR=/user/mapr/$MAPR_CLUSTER

source $MAPR_START_ENV

#Interrupt entrypoint if command overridden
#Here only for testing purposes
#if [[ "$1" == "/bin/bash" ]]; then
#	echo "Found command override, running command"
#	echo "$@"
#	exec "$@"
#fi

#Reset the MAPR hostid to be unique for each container, set hostname to running container hostname
hostid=$(openssl rand -hex 8)
echo "$hostid" > $MAPR_HOME/hostid
conf_hostid=$(basename $MAPR_HOME/conf/hostid.*)
echo "$hostid" > $MAPR_HOME/conf/$conf_hostid
hostname -f | grep $POD_NAME | grep -q -v grep && echo $(hostname -f) > $MAPR_HOME/hostname

#Configure default environment script
echo "#!/bin/bash" > $MAPR_ENV_FILE
echo "export JAVA_HOME=\"$JAVA_HOME\"" >> $MAPR_ENV_FILE
echo "export MAPR_CLUSTER=\"$MAPR_CLUSTER\"" >> $MAPR_ENV_FILE
echo "export MAPR_HOME=\"$MAPR_HOME\"" >> $MAPR_ENV_FILE
[ -f "$MAPR_HOME/bin/mapr" ] && echo "export MAPR_CLASSPATH=\"\$($MAPR_HOME/bin/mapr classpath)\"" >> $MAPR_ENV_FILE
echo "export PATH=\"\$JAVA_HOME:\$PATH:\$MAPR_HOME/bin\"" >> $MAPR_ENV_FILE

#Create the mapr admin user
if id $MAPR_ADMIN >/dev/null 2>&1; then
	echo "Mapr admin user already exists"
else
	$MAPR_CONTAINER_DIR/mapr-create-user.sh $MAPR_ADMIN $MAPR_UID $MAPR_GROUP $MAPR_GID $MAPR_ADMIN_PASSWORD
fi

#configure sshd
if [ ! -d /var/run/sshd ]; then
	mkdir /var/run/sshd
	chpasswd <<<"root:${MAPR_ADMIN_PASSWORD}"

	rm -f /run/nologin
	if [ -f /etc/ssh/sshd_config ]; then
		sed -ri 's/^PermitRootLogin\s+.*/PermitRootLogin yes/' /etc/ssh/sshd_config
		sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config
		sed -ri 's/#UsePAM no/UsePAM no/g' /etc/ssh/sshd_config
		sed -i 's/^ChallengeResponseAuthentication no$/ChallengeResponseAuthentication yes/g' \
			/etc/ssh/sshd_config || echo "Could not enable ChallengeResponseAuthentication"
		echo "ChallengeResponseAuthentication enabled"
	fi

	# SSH login fix. Otherwise user is kicked off after login
	sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
fi

#set memory for container
if [ "$MAPR_ORCHESTRATOR" = "k8s" ]; then
	mem_file="$MAPR_HOME/conf/container_meminfo"
	mem_char=$(echo "$MAPR_MEMORY" | grep -o -E '[kmgKMG]')
	mem_number=$(echo "$MAPR_MEMORY" | grep -o -E '[0-9]+')

	echo "Seting MapR container memory limits..."
	echo "MALLOC_ARENA_MAX=2" >> /etc/environment
	[ ${#mem_number} -eq 0 ] && echo "Empty memory allocation, using default 2G" && mem_number=2
	[ ${#mem_char} -gt 1 ] && echo "Invalid memory allocation: using default 2G" && mem_char=G
	[ $mem_number == "0" ] && echo "Can't use zero, using default 2gG && mem_number=2" && mem_number=2

	case "$mem_char" in
		g|G) mem_total=$(($mem_number * 1024 * 1024)) ;;
		m|M) mem_total=$(($mem_number * 1024)) ;;
		k|K) mem_total=$(($mem_number)) ;;
	esac
	cp -f -v /proc/meminfo $mem_file
	chown $MAPR_ADMIN:$MAPR_GROUP $mem_file
	chmod 644 $mem_file
	sed -i "s!/proc/meminfo!${mem_file}!" "$MAPR_HOME/server/initscripts-common.sh" || \
		echo "Could not edit initscripts-common.sh"
	sed -i "/^MemTotal/ s/^.*$/MemTotal:     $mem_total kB/" "$mem_file" || \
		echo "Could not edit meminfo MemTotal"
	sed -i "/^MemFree/ s/^.*$/MemFree:     $mem_total kB/" "$mem_file" || \
		echo "Could not edit meminfo MemFree"
	sed -i "/^MemAvailable/ s/^.*$/MemAvailable:     $mem_total kB/" "$mem_file" || \
		echo "Could not edit meminfo MemAvailable"
fi

#Configure OS properties
# max processes
ulimit -u ${MAPR_ULIMIT_U:-64000}
# max file descriptors
ulimit -n ${MAPR_ULIMIT_N:-64000}
# max socket connections
sysctl -q -w net.core.somaxconn=${MAPR_SYSCTL_SOMAXCONN:-20000}
# umask 022 instead of non-root 002
umask ${MAPR_UMASK:-022}


#Set variables MAPR_HOME, JAVA_HOME, [ MAPR_SUBNETS (if set)] in conf/env.sh
env_file="$MAPR_HOME/conf/env.sh"
sed -i "s:^#export JAVA_HOME.*:export JAVA_HOME=${JAVA_HOME}:" "$env_file" || \
	echo "Could not edit JAVA_HOME in $env_file"
sed -i "s:^#export MAPR_HOME.*:export MAPR_HOME=${MAPR_HOME}:" "$env_file" || \
	echo "Could not edit MAPR_HOME in $env_file"
if [ -n "$MAPR_SUBNETS" ]; then
	sed -i "s:^#export MAPR_SUBNETS.*:export MAPR_SUBNETS=${MAPR_SUBNETS}:" "$env_file" || \
		echo "Could not edit MAPR_SUBNETS in $env_file"
fi

#Update /etc/hosts file
find_host_ip(){
	cnt=0
	until getent hosts $1; do
		 let cnt++
		 echo "Waiting for MAPR host to resolve, attempt $cnt"
		 [ $cnt -gt 4 ] && check_failed=1 && return
		 sleep 3
	done
}

check_hosts(){
	IFS=',' read -ra RMH <<< "$1"
	node=0
	FQLIST=()
	for i in "${RMH[@]}"; do
        host=$(echo $i | cut -d ':' -f 1)
        
        #fqhost="$host.$NAMESPACE.svc.cluster.local"
        fqhost=$host
        if cat /etc/hosts |grep $fqhost; then
                echo "Found /etc/hosts entry for $fqhost"
        else
                echo "Looking up IP for $fqhost"
                check_failed=0
                find_host_ip $fqhost
                [ $check_failed -eq 0 ] && echo "$(getent hosts $fqhost | awk '{ print $1 }')      $(getent hosts $fqhost | awk '{ print $2 }')      $(echo $fqhost |cut -d '.' -f 1)" >> /etc/hosts
        fi
        let node++
	done
}

#[ -n ${MAPR_CLDB_HOSTS} ] && check_hosts ${MAPR_CLDB_HOSTS}
#[ -n ${MAPR_ZK_HOSTS} ] && check_hosts ${MAPR_ZK_HOSTS}
#[ -n ${MAPR_RM_HOSTS} ] && check_hosts ${MAPR_RM_HOSTS}
#[ -n ${MAPR_HS_HOST} ] && check_hosts ${MAPR_HS_HOST}
#[ -n ${MYSQL_HOST} ] && check_hosts ${MYSQL_HOST}
#[ -n ${MAPR_ES_HOSTS} ] && check_hosts ${MAPR_ES_HOSTS}
#[ -n ${MAPR_OT_HOSTS} ] && check_hosts ${MAPR_OT_HOSTS}
#[ -n ${MAPR_FS_HOSTS} ] && check_hosts ${MAPR_FS_HOSTS}
#[ -n ${MAPR_YARN_HOSTS} ] && check_hosts ${MAPR_YARN_HOSTS}

#echo "MAPR Cluster containers added to /etc/hosts"


#configure mapr services
[ $APL_EVENT -eq 1 ] && notify_apl "Running configure.sh on MAPR node: ${POD_NAME}"

#[ -f $MAPR_DATA_MOUNT/mapr-clusters.conf.bak ] && cp -f $MAPR_DATA_MOUNT/mapr-clusters.conf.bak $MAPR_CLUSTER_CONF

if [ $MAPR_CLIENT -eq 1 ]; then
	if [ -f ${MAPR_HOME}/hadoop/hadoopversion ]; then
		ver=$(cat ${MAPR_HOME}/hadoop/hadoopversion)
	else
		ver=$(ls -lt $MAPR_HOME/hadoop | grep "hadoop-" | head -1 | sed 's/^.*hadoop-//' | awk '{print $1}')
	fi

	HADOOP_CONF=${MAPR_HOME}/hadoop/hadoop-${ver}/etc/hadoop

	if [ -f ${HADOOP_CONF}/core-site.xml ]; then
		#Create the core-site.xml file
		cat > /tmp/core-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!--
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License. See accompanying LICENSE file.
-->

<!-- Put site-specific property overrides in this file. -->

<configuration>
<property>
  <name>fs.mapr.bailout.on.library.mismatch</name>
  <value>false</value>
  <description>Disabling to continue running jobs</description>
</property>
</configuration>
EOF

	mv ${HADOOP_CONF}/core-site.xml ${HADOOP_CONF}/core-site.xml.old
	mv /tmp/core-site.xml ${HADOOP_CONF}/core-site.xml

	fi

fi


if [ -f "$MAPR_CLUSTER_CONF" ]; then
	args=-R
	args="$args -N $MAPR_CLUSTER"
	args="$args -Z $MAPR_ZK_HOSTS"
	args="$args -v"
	echo "Re-configuring MapR services ($args)..."
	$MAPR_CONFIGURE_SCRIPT $args
elif [ $MAPR_CLIENT -eq 1 ]; then
	. $MAPR_HOME/conf/env.sh
	args="$args -c -on-prompt-cont y -N $MAPR_CLUSTER -C $MAPR_CLDB_HOSTS"
	[ -n "$MAPR_TICKETFILE_LOCATION" ] && args="$args -secure"
	[ -n "$MAPR_RM_HOSTS" ] && args="$args -RM $MAPR_RM_HOSTS"
	[ -n "$MAPR_HS_HOST" ] && args="$args -HS $MAPR_HS_HOST"
	args="$args -v"
	echo "Configuring MapR client ($args)..."
	$MAPR_CONFIGURE_SCRIPT $args
else
	. $MAPR_HOME/conf/env.sh
	if [ -n "$MAPR_CLDB_HOSTS" ]; then
		args="$args -f -no-autostart -on-prompt-cont y -N $MAPR_CLUSTER -C $MAPR_CLDB_HOSTS -Z $MAPR_ZK_HOSTS -u $MAPR_ADMIN -g $MAPR_GROUP"
		if [ "$MAPR_SECURITY" = "master" ]; then
			args="$args -secure -genkeys"
		elif [ "$MAPR_SECURITY" = "enabled" ]; then
			args="$args -secure"
		else
			args="$args -unsecure"
		fi
		[ -n "${LICENSE_MODULES##*DATABASE*}" -a -n "${LICENSE_MODULES##*STREAMS*}" ] && args="$args -noDB"
	else
		args="-R $args"
	fi
	[ -n "$MAPR_RM_HOSTS" ] && args="$args -RM $MAPR_RM_HOSTS"
	[ -n "$MAPR_HS_HOST" ] && args="$args -HS $MAPR_HS_HOST"
	[ -n "$MAPR_OT_HOSTS" ] && args="$args -OT $MAPR_OT_HOSTS"
	[ -n "$MAPR_ES_HOSTS" ] && args="$args -ES $MAPR_ES_HOSTS"
	args="$args -v"
	echo "Configuring MapR services ($args)..."
	$MAPR_CONFIGURE_SCRIPT $args
	
	[ -d "$MAPR_DATA_MOUNT" ] && cp -f $MAPR_CLUSTER_CONF $MAPR_DATA_MOUNT/mapr-clusters.conf.bak
fi

if [ -f $MAPR_HOME/roles/fileserver ]; then	
	[ ! -f /data/mapr/storagefile ] && MAPR_RUN_DISKSETUP=1
	[ -n "$REBUILD_NODE" ] && MAPR_RUN_DISKSETUP=1
fi 

#configure the disks
if [ $MAPR_RUN_DISKSETUP -eq 1 ]; then
	[ $APL_EVENT -eq 1 ] && notify_apl "Running disk setup on MAPR node: ${POD_NAME}"
    if [ $USE_FAKE_DISK -eq 1 ]; then
		echo "Setting up psuedo disk for mapr..."
		[ -f /data/mapr/storagefile ] && rm -rf /data/mapr/storagefile
		[ -d /data/mapr ] || mkdir -p /data/mapr
		dd if=/dev/zero of=/data/mapr/storagefile bs=1G seek=20 count=0
		#truncate -s 20G /data/mapr/storagefile
		#fallocate -l 20G /data/mapr/storagefile
		echo "/data/mapr/storagefile" > /tmp/disks.txt
	else
		echo "Setting up $MAPR_DISKS for mapr..."
		echo "$MAPR_DISKS" > /tmp/disks.txt
	fi
	
	sed -i -e 's/mapr/#mapr/g' /etc/security/limits.conf
    sed -i -e 's/AddUdevRules(list(gdevices));/#AddUdevRules(list(gdevices));/g' $MAPR_HOME/server/disksetup
    
    [ $FORCE_FORMAT -eq 1 ] && ARGS="$ARGS -F"
    [ $STRIPE_WIDTH -eq 0 ] && ARGS="$ARGS -M" || ARGS="$ARGS -W $STRIPE_WIDTH"
    $MAPR_DISKSETUP $ARGS /tmp/disks.txt
    if [ $? -eq 0 ]; then
        echo "Local disks formatted for MapR-FS"
    else
        rc=$?
        rm -f /tmp/disks.txt $MAPR_HOME/conf/disktab
        echo "$MAPR_DISKSETUP failed with error code $rc"
    fi
fi

#If a Hive node, Configure
if [ -f $MAPR_HOME/roles/hive ]; then
	[ $APL_EVENT -eq 1 ] && notify_apl "Configuring Hive on MAPR node: ${POD_NAME}"
	echo "Configuring Hive"
	MYSQL_JAR=mysql-connector-java.jar
	#[ "$OS" = "ubuntu" ] && MYSQL_JAR=libmysql-java.jar
	if [ -f ${MAPR_HOME}/hive/hiveversion ]; then
		ver=$(cat ${MAPR_HOME}/hive/hiveversion)
	else
		ver=$(ls -lt $MAPR_HOME/hive | grep "hive-" | head -1 | sed 's/^.*hive-//' | awk '{print $1}')
	fi
	export HIVE_HOME=${MAPR_HOME}/hive/hive-${ver}
	export PATH=$PATH:${HIVE_HOME}/bin
	echo "export HIVE_HOME=\"${MAPR_HOME}/hive/hive-${ver}\"" >> $MAPR_ENV_FILE
	echo "export PATH=\"\$PATH:\$HIVE_HOME/bin\"" >> $MAPR_ENV_FILE
	
	#Create the hive-site.xml file
	cat > /tmp/hive-site.xml << EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!--
   Licensed to the Apache Software Foundation (ASF) under one or more
   contributor license agreements.  See the NOTICE file distributed with
   this work for additional information regarding copyright ownership.
   The ASF licenses this file to You under the Apache License, Version 2.0
   (the "License"); you may not use this file except in compliance with
   the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-->

<configuration>
  <property>
    <name>hive.server2.enable.doAs</name>
    <value>false</value>
    <description>Set this property to enable impersonation in Hive Server 2</description>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/${HIVE_DB}?createDatabaseIfNotExist=true</value>
    <description>JDBC connect string for a JDBC metastore</description>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>com.mysql.jdbc.Driver</value>
    <description>Driver class name for a JDBC metastore</description>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>${HIVE_USER}</value>
    <description>username to use against metastore database</description>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>${HIVE_PASS}</value>
    <description>password to use against metastore database</description>
  </property>
  <property>
    <name>hive.metastore.uris</name>
    <value>thrift://${MAPR_METASTORE_HOST}:9083</value>
  </property>
</configuration>
EOF

	mv ${HIVE_HOME}/conf/hive-site.xml ${HIVE_HOME}/conf/hive-site.xml.old
	mv /tmp/hive-site.xml ${HIVE_HOME}/conf/hive-site.xml
	
	#Initialize the Hive Schema

	if [ -f $MAPR_HOME/roles/hivemetastore ]; then
		echo "Configuring Hive Metastore and Hive Server2"
		ln -s /usr/share/java/${MYSQL_JAR} ${HIVE_HOME}/lib/mysql-connector-java.jar
		$HIVE_HOME/bin/schematool -dbType mysql -initSchema
	fi
fi

#If a Drill Bits node, fix java check
if [ -f $MAPR_HOME/roles/drill-bits ]; then
	echo "Configuring Drill Bits"
	
	ver=$(cat $MAPR_HOME/drill/drillversion)
	DRILL_CONFIG="$MAPR_HOME/drill/drill-${ver}/bin/drill-config.sh"
	DRILL_ENV="$MAPR_HOME/drill/drill-${ver}/conf/drill-env.sh"
	DRILL_WARDEN_CONFIG="$MAPR_HOME/conf/conf.d/warden.drill-bits.conf"

	#Adjust drill memory settings to fit with the demo
	cat >> $DRILL_ENV << EOE
export DRILL_MAX_DIRECT_MEMORY=${DRILL_MAX_DIRECT_MEMORY:-"3G"}
export DRILL_HEAP=${DRILL_HEAP:-"2G"}
export DRILLBIT_MAX_PERM=${DRILLBIT_MAX_PERM:-"512M"}
export DRILLBIT_CODE_CACHE_SIZE=${DRILLBIT_CODE_CACHE_SIZE:-"1G"}
EOE

	#Also update default settings in the warden drillbits conf
	sed -i "s/^service.env=DRILLBIT_MAX_PROC_MEM.*/service.env=DRILLBIT_MAX_PROC_MEM=6G/" "$DRILL_WARDEN_CONFIG"
	sed -i "s/^service.heapsize.min.*/service.heapsize.min=6144/" "$DRILL_WARDEN_CONFIG"
	sed -i "s/^service.heapsize.max.*/service.heapsize.max=6144/" "$DRILL_WARDEN_CONFIG"
	
	#Add fix for java version check so drill will start
	sed -i "s/^\"\$JAVA\" -version .*/\"\$JAVA\" -version 2\>\&1 \| grep \"nothing\" \> \/dev\/null/" "$DRILL_CONFIG"
	
fi

. $MAPR_ENV_FILE

#Add records to start-env
cat >> $MAPR_START_ENV << EOC
CLUSTER_NAME=$MAPR_CLUSTER
MAPR_ADMIN=$MAPR_ADMIN
MAPR_ADMIN_GROUP=$MAPR_GROUP
MAPR_ADMIN_PASS=$MAPR_ADMIN_PASSWORD
MCS_HOST=$MAPR_CLDB_HOSTS
MAPR_MOUNT_PATH=$MAPR_MOUNT_PATH
CLUSTER_INFO_DIR=$CLUSTER_INFO_DIR
EOC

#create log directories for supervisor
mkdir -p /var/log/supervisor
chmod 777 /var/log/supervisor

[ $APL_EVENT -eq 1 ] && notify_apl "Starting services on MAPR node: ${POD_NAME}"
echo "Starting container with command: $@"
[ "$@" = "/bin/bash" ] && echo "Run '/opt/mapr/docker/start-mapr.sh &' or start services manually"
exec "$@"