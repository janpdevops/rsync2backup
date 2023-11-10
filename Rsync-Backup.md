# What is this good for?
TODO

# State of project:
First working breaktrough between client and server; don't use it yet!
## How to build:
The server-image is also the common image. First, build the server image:
 `docker build . -t  janpdevops/rsyncbackup-common`
 Then, you  can build the client image:
 `docker build . -t  janpdevops/rsyncbackup-client` 

## Create the client keys
Go to the client directory and run
`docker compose up`
At first run or if no key is present, this will generate a private key called ssh_key and the public key.

## Start the server with the public key
Put the keys / mount them - TODO
Now, go to the server directory and run also 
`docker compose up`
This opens an ssh-server on port 2222. It allows connections with the Username x. It requires you to use the private part of the public key.

## Rsync your changes
Again, go to the client folder and run
`docker compose up`

This will upload all files in the upload folder.

# TODO
Move hard coded stuff to parameters:
* username
* port
* Mount-Points
* UID
* Make sure, ssh_key has the right permissions.
* Add script to create user on the server host? Do I need this or is numeric ID enough?