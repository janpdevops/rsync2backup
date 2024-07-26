FROM  janpdev/rsyncbackup-common:v0.1

LABEL MAINTAINER JanP janp.dev@googlemail.com
ENV RSYNC_SERVER=127.0.0.1
ENV PUSH=1
# workdir
WORKDIR /data/sshkeys
COPY --chmod=u+x scripts/rsync2backup.sh /usr/bin
RUN chmod u+x /usr/bin/rsync2backup.sh
RUN dos2unix /usr/bin/rsync2backup.sh

COPY scripts/template1.yml /tmp
RUN dos2unix /tmp/template1.yml

COPY scripts/template2.yml /tmp
RUN dos2unix /tmp/template2.yml

ENTRYPOINT ["rsync2backup.sh"]