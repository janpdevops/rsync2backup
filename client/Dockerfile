FROM  janpdevops/rsyncbackup-common:latest

LABEL MAINTAINER JanP janp.dev@googlemail.com

# workdir
WORKDIR /data/sshkeys
COPY --chmod=u+x scripts/rsync2backup.sh /usr/bin
RUN dos2unix /usr/bin/rsync2backup.sh

ENTRYPOINT ["rsync2backup.sh"]