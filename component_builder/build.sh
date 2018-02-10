#!/bin/bash
#mapr server build script

#set environment
MAPR_PKG_GROUPS=( $MAPR_BUILD )
PACKAGES=""
CONTAINER_PORTS=${MAPR_PORTS:-22}
MAPR_LIB_DIR=$MAPR_HOME/lib
MAPR_CORE_VERSION=${MAPR_CORE_VERSION}
MAPR_MEP_VERSION=${MAPR_MEP_VERSION}
MAPR_PKG_URL="${MAPR_PKG_URL:-http://package.mapr.com/releases}"
MAPR_CORE_URL="$MAPR_PKG_URL"
MAPR_ECO_URL="$MAPR_PKG_URL"
SPRVD_CONF="/etc/supervisor/conf.d/maprsvc.conf"
MAPR_START_ENV="${MAPR_CONTAINER_DIR}/start-env.sh"

#MAPR Drill JDBC
MAPRJDBC_HOME="/opt/mapr/jdbc"
DRILL_HOME="/opt/mapr/drill"

PKG_fs="mapr-fileserver"
PORTS_fs="5660 5692"
PKG_nfs="mapr-nfs"
PORTS_nfs="2049 111"
PKG_yarn="mapr-nodemanager"
PORTS_yarn="8041 8042"
PKG_rm="mapr-resourcemanager"
PORTS_rm="8088 8032 19888"
PKG_mrv1="mapr-tasktracker"
PORTS_mrv1="50060 1111"
PKG_jt="mapr-jobtracker"
PORTS_jt="50030"
PKG_zk="mapr-zookeeper"
PORTS_zk="5181 3888 2888"
PKG_mcs="mapr-webserver"
PORTS_mcs="8443"
PKG_cldb="mapr-cldb mapr-fileserver"
PORTS_cldb="5660 5692 7221 7222 1111"
PKG_mon="mapr-collectd"
PKG_log="mapr-fluentd"
PKG_hs="mapr-historyserver"
PORTS_hs="19888"
PKG_sparkmaster="mapr-spark-master mapr-spark-historyserver"
PORTS_sparkmaster="7077 8080 18080"
PKG_spark="mapr-spark"
PORTS_spark="8081"
PKG_edge="mapr-client mapr-posix-client-basic mapr-hbase mapr-asynchbase mapr-spark mapr-hive mapr-kafka mapr-librdkafka"
PORTS_edge=""
PKG_client="mapr-client"
PORTS_client=""
PKG_base="mapr-spark mapr-hive mapr-kafka mapr-librdkafka"
PORTS_base=""
PKG_es="mapr-elasticsearch"
PORTS_es="9200 9300"
PKG_ot="mapr-opentsdb"
PORTS_ot="4242"
PKG_kibana="mapr-kibana"
PORTS_kibana="5601"
PKG_graphana="mapr-graphana"
PORTS_graphana="3000"
PKG_hive="mapr-hive"
PORTS_hive=""
PKG_hiveserver="mapr-hivemetastore mapr-hiveserver2"
PORTS_hive="9083 10000"
PKG_drill="mapr-drill"
PORTS_drill="8047 31010"
PKG_hbrest="mapr-hbase-rest"
PORTS_hbrest="8080"
PKG_gw="mapr-gateway"
PORTS_gw="7660"

START_ZK=0
START_WARDEN=1
START_NFS=0
START_FUSE=0
ADD_MYSQL=0
CREATE_EDGE=0
MAPR_CORE=1
MAPR_CLIENT=0

PKG_LIST=""
PKG_RM=""
PKG_INSTALL=""
MYSQL_PKG=""

#Find the OS type base container is running
if [ "$OS" = "centos" ]; then
	PKG_LIST=(`rpm -qa | grep mapr`)
	PKG_RM="rpm -e"
	PKG_INSTALL="yum install -y"
	PKG_CLEAN="yum -q clean all"
	MYSQL_PKG="mysql-connector-java"
elif [ "$OS" = "ubuntu" ]; then
	export DEBIAN_FRONTEND=noninteractive
	PKG_LIST=(`dpkg -l | grep mapr | awk '{print $2}'`)
	PKG_RM="apt-get purge -y"
	PKG_INSTALL="apt-get install --no-install-recommends -q -y"
	PKG_CLEAN="apt-get autoremove --purge -q -y \&\& rm -rf /var/lib/apt/lists/* \&\& apt-get clean -q"
	MYSQL_PKG="libmysql-java"
else
	echo "MAPR must be run on RedHat, CentOS, or Ubuntu Linux based docker container"
fi
echo "Building MAPR Components on $OS"
if [ $(uname -m) != "x86_64" ]; then
	echo "MAPR must be run on a 64 bit version of Linux"
fi


add_package() {
    PACKAGES="$PACKAGES $(eval "echo \"\$PKG_$1\"")"
        
    CONTAINER_PORTS="$CONTAINER_PORTS $(eval "echo \"\$PORTS_$1\"")"
}

for p in "${MAPR_PKG_GROUPS[@]}"; do
	add_package $p
	
	[ "$p" = zk ] && START_ZK=1
	[ "$p" = nfs ] && START_NFS=1
	[ "$p" = hive ] && ADD_MYSQL=1
	[ "$p" = edge ] && CREATE_EDGE=1
done

echo "Installing the following MAPR packages into image: $PACKAGES"

if [ $CREATE_EDGE -eq 1 ]; then
	hver=$(hadoop version | egrep -o "Hadoop [0-9]+.[0-9]+.[0-9]+" | egrep -o "[0-9]+.[0-9]+.[0-9]+")
	
	echo "$hver" > /opt/mapr/hadoop/hadoopversion
	
	cp -f ${MAPR_HOME}/hadoop/hadoop-${hver}/share/hadoop/yarn/hadoop-yarn-server-web-proxy-${hver}-*.jar /tmp/
	pkgs=${PKG_LIST[@]}
	echo "List of existing mapr package ${pkgs[@]}"
	$PKG_RM ${pkgs[@]}
	
	START_FUSE=1
	START_ZK=0
	START_WARDEN=0
	MAPR_CORE=0
	MAPR_CLIENT=1
fi

#Install the mapr components for this container - added to the core packages
#${MAPR_CONTAINER_DIR}/mapr-setup.sh -r $MAPR_PKG_URL container core $PACKAGES
$PKG_INSTALL $PACKAGES

if [ $CREATE_EDGE -eq 1 ]; then
  	mv /tmp/hadoop-yarn-server-web-proxy-${hver}-*.jar ${MAPR_HOME}/hadoop/hadoop-${hver}/share/hadoop/yarn/

	$PKG_INSTALL unzip

	#Install MAPR JDBC
	echo "Installing MAPR Drill JDBC"
	mkdir -p $MAPRJDBC_HOME
	unzip ${MAPR_CONTAINER_DIR}/lib/DrillJDBC41.zip -d $MAPRJDBC_HOME
	#unzip ${MAPR_CONTAINER_DIR}/lib/DrillJDBC41.zip -d $MAPR_LIB_DIR

	bjar=$(ls $MAPR_LIB_DIR |grep maprfs-6.0.0-mapr-2)
	if [ $? -eq 0 ]; then
		echo "Removing extra maprfs jar file from lib directory"
		rm -rf $MAPR_LIB_DIR/${bjar}
	fi

	#Install Drill Sqlline and JDBC driver
	mkdir -p $DRILL_HOME/jars/jdbc-driver
	mv ${MAPR_CONTAINER_DIR}/lib/drill-jdbc-all-1.11.0.jar $DRILL_HOME/jars/jdbc-driver
fi

[ $ADD_MYSQL -eq 1 ] && $PKG_INSTALL $MYSQL_PKG

MAPR_PORTS=$CONTAINER_PORTS

#Configure MAPR for startup
cat >> $MAPR_START_ENV << EOC
OS=$OS
START_ZK=$START_ZK
START_WARDEN=$START_WARDEN
START_NFS=$START_NFS
START_FUSE=$START_FUSE
MAPR_CORE=$MAPR_CORE
MAPR_CLIENT=$MAPR_CLIENT
EOC


# if [ $START_ZK -eq 1 ]; then
# #configure supervisord to call zookeeper
# 	cat >> $SPRVD_CONF << EOC

# [program:zookeeper]
# command=/etc/init.d/mapr-zookeeper start-foreground
# autorestart=false
# stdout_logfile=/dev/stdout
# stdout_logfile_maxbytes=0
# stderr_logfile=/dev/stderr
# stderr_logfile_maxbytes=0

# EOC

# 	echo "Added MAPR zookeeper to start list"
# fi

# if [ $START_WARDEN -eq 1 ]; then
# #configure supervisord to call warden
# 	cat >> $SPRVD_CONF << EOC

# [program:warden]
# command=/etc/init.d/mapr-warden start
# autorestart=false
# stdout_logfile=/dev/stdout
# stdout_logfile_maxbytes=0
# stderr_logfile=/dev/stderr
# stderr_logfile_maxbytes=0

# EOC

# 	echo "Added MAPR warden to start list"
# fi

if [ $CREATE_EDGE -eq 1 ]; then
#configure supervisord to call mapr start script
	cat >> $SPRVD_CONF << EOC

[program:mapr]
command=${MAPR_CONTAINER_DIR}/start-mapr.sh
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
EOC

	echo "Added MAPR startup script to start list"
fi

#Clean up 
cleanup=( ${PKG_CLEAN} )
rm -rf ${MAPR_CONTAINER_DIR}/lib

exit 0



