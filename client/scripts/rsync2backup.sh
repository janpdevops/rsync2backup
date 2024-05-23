#!/bin/bash


#if no key pair is present, create it
if ! [ -f ssh_key ]; then
	echo "This is the first run, generating your key pair and the docker-compose file for the server"
	echo "Creating keypairs..."
	ssh-keygen -t ed25519  -f ssh_key -N ""
	if ! [ -d public ]; then
		mkdir public
	fi
	mv *.pub public
	echo "Key pair created, you will need them for the client and server part"
	echo "Now create the server part"
	
	# public key goes into docker-file in parameter key 
	# the public key is in between the template1 (with no trailing new line) and template2
	# it is a workaround for replacing a string the public key, because it contains white spaces.
	cat /tmp/template1.yml public/ssh_key.pub /tmp/template2.yml > docker-compose.yml

	sed -i "s/#RSYNC_PORT#/$RSYNC_PORT/g" "docker-compose.yml"	
	sed -i "s/#USER_NAME#/$USER_NAME/g" "docker-compose.yml"
	sed -i "s/#RSYNC_UID#/$RSYNC_UID/g" "docker-compose.yml"
	sed -i "s/#RSYNC_GID#/$RSYNC_GID/g" "docker-compose.yml"
	
	# create add-user-skript, pass it to rsync-server
	# add run script for user @runlevel
else 
# upload the files
# 1s stage ingnore host checking TODO probably check for know-hosts and save it in the key folder
 	 rsync -av --delete -e "ssh -i /data/sshkeys/ssh_key  -o \"StrictHostKeyChecking no\"  -p ${RSYNC_PORT} " /upload ${USER_NAME}@${RSYNC_SERVER}:/data
	 cp -r ~/.ssh .
fi