# Backup

Gesichert wird täglich um **03:15** (Zeitzone des Containers: Europe/Berlin), durch den
Service `backup` im Stack selbst — kein Host-Cron, kein systemd-Timer. Der Zeitplan
zieht damit mit, wenn der Stack umzieht.

## Was gesichert wird

| | warum |
|---|---|
| Datenbank-Dump (`mariadb-dump --single-transaction`) | die eigentliche Buchhaltung |
| `private/files` und `public/files` der Site | **die hochgeladenen Belege** |
| `site_config.json` + `common_site_config.json` | enthält den `encryption_key` — ohne ihn sind gespeicherte Passwörter und OAuth-Secrets nach einem Restore unbrauchbar |

Ein reiner Datenbank-Dump reicht ausdrücklich **nicht**: ohne die `files`-Verzeichnisse
sind alle Rechnungen und Belege weg, ohne den `encryption_key` sind die Zugangsdaten hin.

Der Container mountet das `sites`-Volume **read-only**. Ein Backup darf die Nutzdaten
unter keinen Umständen verändern.

## Wohin

**Primär — rammstein (10.0.0.100):** restic-Repo unter `/data/backups/erpnext/repo`,
erreicht per SFTP. Der dafür hinterlegte SSH-Key ist in rammsteins `authorized_keys`
eingeschränkt auf:

```
command="/usr/lib/openssh/sftp-server -d /data/backups/erpnext",restrict
```

Der Key kann also ausschließlich SFTP in genau diesem Verzeichnis — keine Shell, kein
Port-Forwarding, kein Zugriff auf den Rest des Servers.

**Offsite — vorbereitet, noch nicht aktiv.** Sobald ein Ziel existiert, reicht das
Setzen von zwei bis drei Environment-Variablen in Coolify, ein Redeploy, fertig:

```
RESTIC_REPOSITORY_OFFSITE=sftp:u123456@u123456.your-storagebox.de:/erpnext
# oder S3-kompatibel:
RESTIC_REPOSITORY_OFFSITE=s3:https://s3.example.com/fs-backups/erpnext
OFFSITE_ACCESS_KEY_ID=...
OFFSITE_SECRET_ACCESS_KEY=...
```

Bei einem SFTP-Ziel muss der öffentliche Schlüssel aus `BACKUP_SSH_KEY_B64` dort
hinterlegt werden. Das gleiche restic-Passwort wird für beide Repos verwendet.

Warum restic und nicht einfach `scp` einer `.sql.gz`: Versionierung mit
Deduplizierung (14 Tage / 8 Wochen / 12 Monate passen in wenige hundert MB),
Verschlüsselung am Client — auf rammstein liegt nichts im Klartext — und ein
`restic check` je Lauf.

## Benachrichtigung bei Fehlschlag

Zwei Wege, beide über eine Environment-Variable scharfgeschaltet:

| Variable | wird aufgerufen | fängt ab |
|---|---|---|
| `BACKUP_PUSH_URL` | nur bei **Erfolg** | Uptime-Kuma-Push-Monitor: bleibt der Ping aus, schlägt Kuma von selbst Alarm — erkennt also auch „Backup lief gar nicht" |
| `BACKUP_WEBHOOK_URL` | nur bei **Fehlschlag** | sofortige Meldung mit dem fehlgeschlagenen Schritt, z. B. als Discord-Webhook |

Die Kombination ist Absicht. Ein Webhook, der nur bei Fehlern feuert, ist blind für den
häufigsten realen Fall: der Job läuft überhaupt nicht mehr, und niemand merkt es. Genau
das ist der Ausfallmodus, der uns bei der Bestandsaufnahme am 12.09. um ein Haar teuer
geworden wäre.

Zusätzlich beendet sich ein fehlgeschlagener Lauf mit Exit-Code 1 und schreibt den Status
nach `/tmp/last-backup-status` im Container; die Logs stehen in Coolify unter dem Service
`backup`.

## Wiederherstellung

```bash
# auf slipknot (Root-Shell dort ist fish -> Skripte immer ueber bash -s)
CT=$(docker ps --filter name=backup- -q | head -1)

# Snapshots ansehen
docker exec -e RESTIC_PASSWORD=... -e RESTIC_REPOSITORY=sftp:backup-target:/data/backups/erpnext/repo \
  "$CT" restic snapshots

# gewuenschten Snapshot auspacken
docker exec ... "$CT" restic restore <snapshot-id> --target /restore

# Datenbank zurueckspielen (im backend-Container)
BCT=$(docker ps --filter name=backend- -q | head -1)
docker exec "$BCT" bench --site erp.nak-studis.de restore /pfad/zum/dump.sql.gz
```

Die `files`-Verzeichnisse werden anschließend zurück in das `sites`-Volume kopiert und
`site_config.json` geprüft — insbesondere der `encryption_key`.

**Ein Backup, das nie zurückgespielt wurde, ist kein Backup.** Ein Restore-Test auf einer
Wegwerf-Site gehört einmal gemacht, bevor man sich darauf verlässt.

## Das restic-Passwort

`RESTIC_PASSWORD` steht in den Coolify-Environment-Variables. **Ohne dieses Passwort ist
kein einziges Backup wiederherstellbar** — restic verschlüsselt clientseitig, es gibt
keine Hintertür. Es gehört zusätzlich in den Vaultwarden der Fachschaft, und zwar an eine
Stelle, die auch dann erreichbar ist, wenn slipknot weg ist.
