# Backup-Container für den ERPNext-Stack.
# Bewusst schlank (Alpine statt des 2-GB-Frappe-Images): er braucht nur einen
# MariaDB-Client für den Dump, restic für Versionierung/Verschlüsselung und
# einen SSH-Client für das SFTP-Ziel auf rammstein.
FROM alpine:3.22

RUN apk add --no-cache \
      restic \
      openssh-client \
      mariadb-client \
      gzip tar curl tzdata bash coreutils

ENV TZ=Europe/Berlin
COPY run-backup.sh /usr/local/bin/run-backup.sh
COPY notify.sh     /usr/local/bin/notify.sh
COPY loop.sh        /usr/local/bin/loop.sh
RUN chmod +x /usr/local/bin/run-backup.sh /usr/local/bin/loop.sh

ENTRYPOINT ["/usr/local/bin/loop.sh"]
