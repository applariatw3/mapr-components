#!/bin/bash
#Create a user for mapr environment, defaults to the MAPR admin user
#This script replaces the create_user function in mapr-setup.sh since we are not using 
#mapr-setup.sh to "start" the container
#This script is called by entrypoint.sh with command line arguments User UID Group GID Password
#TO DO: update to argument flags or embed as function in entrypoint.sh

NEW_USER=${1:-mapr}
NEW_UID=${2:-5000}
NEW_GROUP=${3:-mapr}
NEW_GID=${4:-5000}
NEW_USER_PASSWORD=${5:-mapr522301}
MAPR_SUDOERS_FILE="/etc/sudoers.d/mapr_user"


if getent group $NEW_GID > /dev/null 2>&1 ; then
    echo "Group ID already exists"
else
	groupadd -g $NEW_GID $NEW_GROUP
	
	[ $? -ne 0 ] && echo "There was a problem creating the MAPR Group ID" && exit 5
fi

if getent passwd $NEW_UID > /dev/null 2>&1 ; then
    echo "User ID already exists"
else
	useradd -m -u $NEW_UID -g $NEW_GID -G $(stat -c '%G' /etc/shadow) $NEW_USER 
	
	[ $? -ne 0 ] && echo "There was a problem creating the MAPR Group ID" && exit 5
	
	echo "MAPR user added to container"
fi

#echo $NEW_USER_PASSWORD | passwd $NEW_USER --stdin
chpasswd <<<"$NEW_USER:$NEW_USER_PASSWORD"

cat > $MAPR_SUDOERS_FILE << EOM
$NEW_USER	ALL=(ALL)	NOPASSWD:ALL
Defaults:$NEW_USER		!requiretty
EOM
chmod 0440 $MAPR_SUDOERS_FILE

#set user environment
if [ -d /home/$NEW_USER ]; then
	echo "Setting environment for $NEW_USER"
	echo ". $MAPR_ENV_FILE" >> /home/$NEW_USER/.bashrc
	
	mkdir -m 700 -p /home/$NEW_USER/.ssh

	[ -f $MAPR_CONTAINER_DIR/keys/${NEW_USER}_key ] && \
	  mv $MAPR_CONTAINER_DIR/keys/${NEW_USER}_key /home/$NEW_USER/.ssh/id_rsa && \
	  chmod 600 /home/$NEW_USER/.ssh/id_rsa
	[ -f $MAPR_CONTAINER_DIR/keys/${NEW_USER}_key.pub ] && \ls 
	  mv $MAPR_CONTAINER_DIR/keys/${NEW_USER}_key.pub /home/$NEW_USER/.ssh/id_rsa.pub && \
	  cat /home/$NEW_USER/.ssh/id_rsa.pub >> /home/$NEW_USER/.ssh/authorized_keys && \
	  chmod 644 /home/$NEW_USER/.ssh/id_rsa.pub /home/$NEW_USER/.ssh/authorized_keys
	[ -f $MAPR_CONTAINER_DIR/keys/authorized_keys ] && \
	  cat $MAPR_CONTAINER_DIR/keys/authorized_keys >> /home/$NEW_USER/.ssh/authorized_keys && \
	  chmod 644 /home/$NEW_USER/.ssh/authorized_keys
	  
	echo "StrictHostKeyChecking no" >> /home/$NEW_USER/.ssh/config
	chmod 600 /home/$NEW_USER/.ssh/config
	  
	chown -R ${NEW_USER}:${NEW_GROUP} /home/$NEW_USER/.ssh
else
	echo "Home directory for $NEW_USER does not exist, exiting"
	exit 6
fi

exit 0

