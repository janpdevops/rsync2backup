FROM linuxserver/openssh-server:latest

LABEL org.opencontainers.image.authors="janp.dev@googlemail.com"
LABEL org.opencontainers.image.version="0.1"

# Install rsync for server-side backup operations
RUN apk add --no-cache --upgrade rsync

# TODO: Pin this image to a specific version tag for reproducibility
#       (currently using :latest to ensure availability)
# TODO: Restrict SSH access to rsync-only via authorized_keys 'command="rrsync -wo /data"' option
# TODO: Add AllowUsers directive to sshd_config for the transfer user only

