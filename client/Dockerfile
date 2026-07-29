FROM janpdev/rsyncbackup-common:v0.1

LABEL org.opencontainers.image.authors="janp.dev@googlemail.com"
LABEL org.opencontainers.image.version="0.1"

ENV RSYNC_SERVER=127.0.0.1
ENV PUSH=1

# workdir
WORKDIR /data/sshkeys

COPY --chmod=u+x scripts/rsync2backup.sh /usr/bin/
COPY scripts/template1.yml /tmp/
COPY scripts/template2.yml /tmp/

# Convert line endings (needed if copying from Windows)
# and squash into a single RUN to reduce layers
RUN dos2unix /usr/bin/rsync2backup.sh /tmp/template1.yml /tmp/template2.yml \
    && chmod u+x /usr/bin/rsync2backup.sh

ENTRYPOINT ["rsync2backup.sh"]