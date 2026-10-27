# Backup

Gesichert wird täglich um **03:15** (Europe/Berlin) durch den CronJob `backup` im Namespace `erpnext`
(Repo `gitops`, `apps/erpnext/backup.yaml`), mit dem Image aus `backup/` dieses Repos
(`ghcr.io/fachschaft-informatik-nordakademie/fs-erpnext-backup`). Jeder Lauf prüft danach den neuesten
Snapshot: Dump vorhanden, nicht winzig, vollständig, `restic check` ohne Befund. Sonst gilt der Lauf als
fehlgeschlagen.

## Was gesichert wird

| | warum |
|---|---|
| Datenbank-Dump (`mariadb-dump --single-transaction`, unkomprimiert) | die eigentliche Buchhaltung |
| `private/files` und `public/files` der Site | **die hochgeladenen Belege** |
| `site_config.json` + `common_site_config.json` | enthält den `encryption_key` — ohne ihn sind gespeicherte Passwörter und OAuth-Secrets nach einem Restore unbrauchbar |

Ein reiner Datenbank-Dump reicht ausdrücklich **nicht**: ohne die `files`-Verzeichnisse
sind alle Rechnungen und Belege weg, ohne den `encryption_key` sind die Zugangsdaten hin.

Der Job mountet das `sites`-Volume **read-only**. Ein Backup darf die Nutzdaten
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

**Offsite — vorbereitet, noch nicht aktiv.** Sobald ein Ziel existiert, reicht es, zwei bis drei Werte in
OpenBao unter `kv/erpnext/backup` zu ergänzen (der Job liest das ganze Secret als Umgebung; die S3-Schlüssel
heißen dort `AWS_ACCESS_KEY_ID` und `AWS_SECRET_ACCESS_KEY`):

```
RESTIC_REPOSITORY_OFFSITE=sftp:u123456@u123456.your-storagebox.de:/erpnext
# oder S3-kompatibel:
RESTIC_REPOSITORY_OFFSITE=s3:https://s3.example.com/fs-backups/erpnext
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
```

Bei einem SFTP-Ziel muss der öffentliche Schlüssel aus `BACKUP_SSH_KEY_B64` dort
hinterlegt werden. Das gleiche restic-Passwort wird für beide Repos verwendet.

Der Dump wird bewusst **unkomprimiert** abgelegt und restic überlassen. Ein gzip-Dump
sieht nach jeder noch so kleinen Änderung byteweise komplett anders aus — dann legt jeder
Lauf den ganzen Dump neu ab. Unkomprimiert greift restics Deduplizierung, und ein
täglicher Snapshot kostet nur noch das echte Delta statt jedes Mal die volle Dumpgröße.

Warum restic und nicht einfach `scp` einer `.sql.gz`: Versionierung mit
Deduplizierung (14 Tage / 8 Wochen / 12 Monate passen in wenige hundert MB),
Verschlüsselung am Client — auf rammstein liegt nichts im Klartext — und ein
`restic check` je Lauf.

## Benachrichtigung bei Fehlschlag

Drei Wege, jeweils über eine Environment-Variable scharfgeschaltet (Code: `backup/notify.sh`, Tests: `bash tests/test_notify.sh`):

| Variable | wird aufgerufen | fängt ab |
|---|---|---|
| `BACKUP_PUSH_URL` | nur bei **Erfolg** | Uptime-Kuma-Push-Monitor: bleibt der Ping aus, schlägt Kuma von selbst Alarm — erkennt also auch „Backup lief gar nicht". **Noch nicht gesetzt.** |
| `BACKUP_ALERT_URL` | bei **Fehlschlag** (firing) und **Erfolg** (resolved) | Alerts-Manager von infrastructure-scripts (`http://10.0.0.100:8781/relay/alert/<secret>`, Secret im Vault "Coolify Relay Secret (infrastructure-scripts)"). Fehlschlag = offener Alert in 🗄️-notifications mit `@here` (critical), Erfolg = die Nachricht verschwindet. Gesetzt mit `BACKUP_ALERT_SOURCE=infrastructure-scripts` und `BACKUP_ALERT_KEY=job:erpnext-backup`, dem Key des früheren infrastructure-scripts-Jobs, damit bestehende Alerts weiter zusammenpassen. |
| `BACKUP_WEBHOOK_URL` | nur bei **Fehlschlag**, und nur wenn `BACKUP_ALERT_URL` leer oder der Manager nicht erreichbar ist | Discord-Webhook der Fachschaft direkt: `@here`-Ping plus roter Embed (Fallback, fail open) |

Die Kombination ist Absicht. Ein Webhook, der nur bei Fehlern feuert, ist blind für den
häufigsten realen Fall: der Job läuft überhaupt nicht mehr, und niemand merkt es. Genau
das ist der Ausfallmodus, der uns bei der Bestandsaufnahme am 12.09. um ein Haar teuer
geworden wäre.

Zusätzlich endet ein fehlgeschlagener Lauf mit Exit-Code 1, der Job steht dann auf `Failed`. Logs:
`kubectl -n erpnext logs job/<job>`; einen Lauf sofort nachholen:
`kubectl -n erpnext create job --from=cronjob/backup backup-manual`.

## Wiederherstellung

Ein Pod mit dem Backup-Image und allen Zugangsdaten, der nichts sichert:

```bash
kubectl -n erpnext create job --from=cronjob/backup restore --dry-run=client -o yaml > restore.yaml
# in restore.yaml: command: [sleep, "86400"]
kubectl apply -f restore.yaml
kubectl -n erpnext exec -it job/restore -- bash
```

Darin die SSH-Konfiguration so anlegen wie `setup_ssh` in `backup/run-backup.sh`, dann:

```bash
restic -r "$RESTIC_REPOSITORY_PRIMARY" snapshots
restic -r "$RESTIC_REPOSITORY_PRIMARY" restore <snapshot-id> --target /work/restore
```

Die Datenbank spielt der backend-Container zurück:
`kubectl -n erpnext exec -it deploy/erpnext -c backend -- bench --site erp.nak-studis.de restore <dump.sql>`.
Danach `kubectl -n erpnext delete job restore`.

Die `files`-Verzeichnisse werden anschließend zurück in das `sites`-Volume kopiert und
`site_config.json` geprüft — insbesondere der `encryption_key`.

**Ein Backup, das nie zurückgespielt wurde, ist kein Backup.** Ein Restore-Test auf einer
Wegwerf-Site gehört einmal gemacht, bevor man sich darauf verlässt.

## Das restic-Passwort

`RESTIC_PASSWORD` steht in OpenBao unter `kv/erpnext/backup`. **Ohne dieses Passwort ist
kein einziges Backup wiederherstellbar** — restic verschlüsselt clientseitig, es gibt
keine Hintertür. Es gehört zusätzlich in den Vaultwarden der Fachschaft, und zwar an eine
Stelle, die auch dann erreichbar ist, wenn der Cluster weg ist.
