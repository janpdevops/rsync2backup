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
 	 rsync -av --delete -e "ssh -i /data/sshkeys/ssh_key  -o \"StrictHostKeyChecking no\"  -p ${RSYNC_PORT} " /upload ${USER_NAME}@${RSYNC_SERVER}:/data
fi
# create add-user-skript, pass it to rsync-server

# add run script for user @runlevel
echo $RSYNC_UID
echo replace UID in template
echo replace USER in template
echo replace Port in template

echo key goes into docker-file in parameter key
#PUB_KEY="Horst Koehler" # Ohne Anfuerhungszeichen nicht.
#PUB_KEY=$(cat public/ssh_key.pub)
#PUB_KEY="$PUB_KEY" # versuch. Anfuerhungszeichen hinzufuegen

echo aaaaaaaa
echo $PUB_KEY
echo bbbbbbbb

cat /tmp/template1.yml public/ssh_key.pub /tmp/template2.yml > docker-compose-template.yml

#sed -i "s/#PUB_KEY#/Alpha beta gamma/g" "docker-compose-template.yml" # works
#sed -i "y/#PUB_KEY#/$PUB_KEY/g" "docker-compose-template.yml"
sed -i "s/#RSYNC_PORT#/$RSYNC_PORT/g" "docker-compose-template.yml"
sed -i "s/#USER_NAME#/$USER_NAME/g" "docker-compose-template.yml"
sed -i "s/#RSYNC_UID#/$RSYNC_UID/g" "docker-compose-template.yml"
sed -i "s/#RSYNC_GID#/$RSYNC_GID/g" "docker-compose-template.yml"

#echo awk '{sub(/#PUB_KEY#/,$PUB_KEY); print}' docker-compose-template.yml
#awk '{sub(/#PUB_KEY#/,$PUB_KEY); print}' docker-compose-template.yml
#echo awk "{sub(/#PUB_KEY#/,$PUB_KEY); print}" docker-compose-template.yml
#awk "{sub(/#PUB_KEY#/,$PUB_KEY); print}" docker-compose-template.yml

#echo awk '{sub(/#RSYNC_PORT#/,$RSYNC_PORT); print}' docker-compose-template.yml
#awk '{sub(/#RSYNC_PORT#/,$RSYNC_PORT); print}' docker-compose-template.yml

#echo awk '{sub(/#USER_NAME#/,$USER_NAME); print}' docker-compose-template.yml
#awk '{sub(/#USER_NAME#/,$USER_NAME); print}' docker-compose-template.yml

#awk "{sub(/{#PUB_KEY#}/,{$PUB_KEY}); print}" {"docker-compose-template.yml"}
#awk '{sub(/{#RSYNC_PORT#}/,{$RSYNC_PORT}); print}' {"docker-compose-template.yml"}
#awk "{sub(/{#USER_NAME#}/,{$USER_NAME}); print}" {"docker-compose-template.yml"}

#awk 'BEGIN { print "var1=" ARGV[1] "\n" "var2=" ARGV[2] }' docker-compose-template.yml "$PUB_KEY" # 2 is pub key
#awk 'BEGIN {sub(/#PUB_KEY#/,ARGV[1]); print}' docker-compose-template.yml "$PUB_KEY"
#awk 'BEGIN {sub(/#PUB_KEY#/,ARGV[1]); print}' "$PUB_KEY" docker-compose-template.yml 
#awk '{sub(/#PUB_KEY#/,ARGV[1]); print}'  "$PUB_KEY" docker-compose-template.yml

cat docker-compose-template.yml