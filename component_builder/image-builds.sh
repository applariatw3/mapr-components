#!/bin/bash
#Script to build mapr images
all=()
all+=("zk" "cldb-mcs")
all+=("drill")
all+=("rm" "yarn")
all+=("hive")
all+=("spark-yarn")
all+=("full-data")
all+=("fs")
all+=("edge")
all+=("client")
all+=("gw")
all+=("base")
usage="$(basename "$0") all || [ ${all[@]} ]"

CORE_TAG=6.0.0_4.0.0_ubuntu14
REPO_ACCT=applariat
REPO_TAG=6.0.0_4.0.0
TAG_LATEST=1
IMAGE_PUSH=1

build_image() {
	local IMAGE_NAME=$1 
	shift 1
	./docker-build.sh $REPO_ACCT $IMAGE_NAME $REPO_TAG $TAG_LATEST $IMAGE_PUSH "$@"
}

build=()


if [ "$1" = "all" ]; then
	build=( "${all[@]}" )
elif [ "$1" = "-h" ]; then
	echo "Build Options, $usage"
	exit 0
elif [ $# -eq 0 ]; then
	echo "Building All, $usage"
	build=( "${all[@]}" )
else
	build=( "$@" )
fi

for i in ${build[@]}; do
	case "$i" in
	zk) 		echo "Building zookeeper"
				#zookeeper
				build_image mapr-zk zk
				;;
	cldb) 		echo "Building CLDB"
				#cldb
				build_image mapr-cldb cldb 
				;;
	cldb-mcs) 	echo "Building CLDB-MCS"
				#cldb-mcs
				build_image mapr-cldb-mcs cldb mcs
				;;
	mcs)		echo "Building MCS"
				#mcs
				build_image mapr-mcs mcs
				;;
	fs)			echo "Building Fileserver"
				#fs
				build_image mapr-base-data fs
				;;
	drill)		echo "Building Drill"
				#drill
				build_image mapr-drill drill fs
				;;
	rm)			echo "Building RM"
				#rm
				build_image mapr-rm rm hs fs
				;;
	yarn)		echo "Building YARN"
				#yarn
				build_image mapr-yarn yarn fs
				;;
	mrv1)		echo "Building MRV1"
				#mrv1
				build_image mapr-mrv1 mrv1 fs
				;;
	jt)			echo "Building Job Tracker"
				#jt
				build_image mapr-jt jt fs
				;;
	es)			echo "Building Elasticsearch"
				#es
				build_image mapr-es es kibana
				;;
	ot)			echo "Building Open TSDB"
				#ot
				build_image mapr-ot ot graphana
				;;
	edge)		echo "Building Edge"
				#edge
				build_image mapr-edge edge
				;;
	client)		echo "Building Base Client"
				#edge
				build_image mapr-base-client client
				;;
	hive)		echo "Building Hive"
				#hive
				build_image mapr-hive fs hive hiveserver
				;;
	spark-yarn)	echo "Building Spark"
				#spark yarn
				build_image mapr-spark-yarn fs yarn spark
				;;
	full-data)	echo "Building Full Data Node"
				#full data
				build_image mapr-full-data fs yarn spark hive drill
				;;
	spark-mst)	echo "Building Spark Master"
				#spark
				build_image mapr-spark-master fs sparkmaster
				;;
	spark)		echo "Building Spark"
				#spark
				build_image mapr-spark fs spark
				;;
	nfs)		echo "Building NFS"
				#nfs
				build_image mapr-nfs nfs fs
				;;
	gw)			echo "Building Gateway"
				#gw
				build_image mapr-gw gw
				;;
	base)		echo "Building base"
				#base with clients
				build_image mapr-base base
				;;
	*)			echo $usage
				;;
	esac
done


exit
