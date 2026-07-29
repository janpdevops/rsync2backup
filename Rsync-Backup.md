# What is this good for?
`rsync2backup` is a first step toward a simple, cross-platform backup solution.

The goal of this project is to synchronize the contents of a local filesystem (e.g., on a notebook, desktop computer, or server)
with a remote filesystem (the backup destination) via `rsync` over SSH.

The core ideas:
* **Cross-platform**: The client and server each run as Docker containers. This means it doesn't matter whether you run the rsync client on Windows, Linux, or macOS – all you need is a working Docker or Docker Compose installation. The actual synchronization happens inside the container using standard Linux tools (`rsync`, `ssh`).
* **Client/Server Architecture**:
  * The **Client** (`client/`) connects to the server via SSH/`rsync` and uploads files from a mounted `upload` directory (push mode) or downloads them (pull mode).
  * The **Server** (`server/`) is based on an `openssh-server` image with `rsync` installed and handles incoming client connections. Access is controlled exclusively via SSH public-key authentication.
* **Easy Setup**: On first run, the client automatically generates an SSH key pair and a matching `docker-compose.yml` for the server, so the public key is ready for server-side deployment.
* **Repeatable Synchronization**: After initial setup, a simple `docker compose up` on the client side synchronizes the configured directories with the server (including deleting files no longer present in push mode via `rsync --delete`).

In short: A lightweight, containerized rsync-over-SSH setup that serves as a first step toward a complete, operating-system-independent backup solution.

# State of project:
First working breaktrough between client and server; don't use it yet!
## How to build:
The server-image is also the common image. First, build the server image:
 `docker build . -t  janpdev/rsyncbackup-common:v0.1`
 Then, you  can build the client image:
 `docker build . -t  janpdev/rsyncbackup-client:v0.1` 
 
(Upload via docker push  janpdev/rsyncbackup-common:v0.1 )

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