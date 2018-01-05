FROM applariat/mapr-core:6.0.0_4.0.0_ubuntu14
#Starting from mapr core image

ARG MAPR_BUILD
ENV MAPR_BUILD=${MAPR_BUILD:-"cldb-mcs"} \
	MAPR_PORTS=22
ENV container docker

#Copy files into place 
COPY build.sh entrypoint.sh scripts/ $MAPR_CONTAINER_DIR/
COPY lib/ $MAPR_CONTAINER_DIR/lib
RUN chmod +x *.sh

WORKDIR $MAPR_CONTAINER_DIR

#Install mapr packages
RUN ./build.sh

EXPOSE $MAPR_PORTS

ENTRYPOINT ["./entrypoint.sh"]

CMD ["/opt/mapr/docker/start-mapr.sh"]
