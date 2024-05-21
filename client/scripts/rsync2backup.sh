#!/bin/bash


#if no key pair is present, create it
if ! [ -f ssh_key ]; then
	echo "Creating keypairs..."
	ssh-keygen -t ed25519  -f ssh_key -N ""
	if ! [ -d public ]; then
		mkdir public
	fi
	mv *.pub public
	echo "Key pair created, you will need them for the client and server part"
	echo "Now create the server part"
else 
# upload the files
 	 rsync -av --delete -e "ssh -i /data/sshkeys/ssh_key  -o \"StrictHostKeyChecking no\"  -p ${RSYNC_PORT} " /upload transfer@${RSYNC_SERVER}:/data
fi
# create add-user-skript, pass it to rsync-server