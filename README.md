# ERPNext — Buchhaltung der Fachschaft Informatik e.V.

Selbstgehostete Vereinsbuchhaltung auf Basis von [ERPNext](https://erpnext.com) (GPLv3).
Läuft im Kubernetes-Cluster der Fachschaft (Repo `gitops`, `apps/erpnext`); hier liegen Image und Backup.

## Warum ERPNext

Der Verein ist **nicht gemeinnützig** und liegt mit über 25.000 € Mitgliedsbeiträgen
**über der Kleinunternehmergrenze** (§ 19 UStG, 25.000 €) — es fällt also Umsatzsteuer an,
mit Vorsteuerabzug. Gleichzeitig soll der Gewinn je Veranstaltung und je Veranstaltungsreihe
auswertbar sein, es sollen Belege am Vorgang hängen, und es soll mehrbenutzerfähig mit
Authentik-Login laufen.

Die schlanken Vereins-Tools scheitern an der Umsatzsteuer (die Nextcloud-App
`vereinsbuchhaltung` sagt selbst: „kein Steuerprogramm"), JVerein ist ein Desktop-Client
ohne OIDC. ERPNext deckt als einziges freies Werkzeug alles ab:

| Anforderung | Umsetzung in ERPNext |
|---|---|
| Gewinn je Veranstaltung | Kostenstelle je Event |
| Gewinn je Veranstaltungsreihe | Kostenstellen sind ein Baum — Reihe ist die Elternkostenstelle |
| Umsatzsteuer / Vorsteuer | Steuervorlagen 19 % / 7 % / Vorsteuer |
| Belege | Anhänge an jedem Beleg |
| Abschreibungen | Anlagenmodul mit AfA-Plan |
| Mehrbenutzer + SSO | Rollen + Social Login Key (OIDC) gegen Authentik |
| Weitergabe an die Steuerberatung | DATEV-Export (`erpnext_datev`, im Image enthalten) |
| Rechnungen und Mahnungen verschicken | eigenes Postfach `erp@nak-studis.de`, siehe [docs/MAIL.md](docs/MAIL.md) |
| Deutsche Pflichten | `erpnext_germany`: lückenlose Nummernkreise, Löschschutz für Anhänge an gebuchten Belegen, Summen- und Saldenliste, GDPdU-Export für die Betriebsprüfung |
| E-Rechnung | `eu_einvoice`: XRechnung/ZUGFeRD empfangen und erstellen — seit 01.01.2025 muss der Verein als Unternehmer E-Rechnungen empfangen können |

Was ERPNext **nicht** kann: ELSTER. Die Umsatzsteuer-Voranmeldung wird entweder aus dem
Bordbericht in ELSTER-Online übertragen oder per DATEV-Export an die Steuerberatung gegeben.
Beide Wege sind vorbereitet, siehe [docs/UMSATZSTEUER.md](docs/UMSATZSTEUER.md).

## Wo das läuft

| | |
|---|---|
| Adresse | https://erp.nak-studis.de |
| Manifeste | Repo `gitops`, `apps/erpnext` (Namespace `erpnext`), seit 27.10.2026 |
| Daten | Longhorn-Volumes `db-data` (MariaDB) und `sites` (Belege, Site-Konfiguration) |

## Struktur

```
docker-compose.yaml   Stack für eine lokale Instanz (früher der Coolify-Stack)
.env.example          alle Variablen der Compose-Datei mit Erklärung
backup/               Backup-Image (CronJob im Cluster), Tests in tests/
apps.json             welche Apps ins Image gebaut werden (gepinnte Versionen)
.github/workflows/    baut das Image nach ghcr.io
docs/AUTHENTIK.md     SSO-Einrichtung
docs/MAIL.md          Mailversand über erp@nak-studis.de
docs/DEUTSCHE-APPS.md erpnext_germany und eu_einvoice: was sie können, was noch fehlt
docs/UMSATZSTEUER.md  UStVA: Bordbericht-Weg und DATEV-Weg
docs/KONTIERUNG.md    Kontenrahmen, Kostenstellen, Events und Eventreihen
```

## Der `create-site`-Trick

In der Compose-Datei braucht ERPNext einen einmaligen Init-Schritt (`bench new-site`), der sonst
als „dauerhaft ungesunder Container" auffällt. Gelöst wie bei `lan-homepage` (nak-lan.de):

```yaml
create-site:
  restart: "no"
  # ... legt die Site an, oder überspringt, wenn sie existiert
backend:
  depends_on:
    create-site:
      condition: service_completed_successfully
```

`create-site` läuft bei jedem Deploy, prüft `sites/<SITE_NAME>` und beendet sich mit 0,
wenn nichts zu tun ist. Damit ist der Stack idempotent redeploybar.

## Das Image

Die Instanz läuft **nicht** auf `frappe/erpnext`, sondern auf einem selbstgebauten Image
`ghcr.io/fachschaft-informatik-nordakademie/fs-erpnext`. Grund: ERPNext allein reicht
nicht, es braucht drei Zusatz-Apps von [ALYF](https://github.com/alyf-de) —
`erpnext_germany` (deutsche Pflichten), `eu_einvoice` (XRechnung/ZUGFeRD) und
`erpnext_datev` (Export an die Steuerberatung). Frappe-Apps lassen sich nicht nachträglich
in einen laufenden Container legen, sie müssen ins Image.

Gebaut wird über `.github/workflows/build-image.yml` — der Workflow läuft automatisch bei
jeder Änderung an `apps.json` und ist auch von Hand startbar. Das Ergebnis bekommt zwei
Tags: die ERPNext-Version (`v16.35.0`) und den Commit-SHA. **In `apps/erpnext/kustomization.yaml` steht der SHA**,
denn den Versions-Tag schiebt jeder neue Build weiter, der SHA-Tag nicht.

`apps.json` reicht frappe_docker als **Build-Secret** herein (`secret-files: apps_json=apps.json`),
nicht als Build-Arg `APPS_JSON_BASE64` — das wertet `images/layered/Containerfile` nicht
mehr aus. Wird das verwechselt, läuft der Build ohne Fehlermeldung durch und das Image
enthält am Ende nur `frappe`. Ein Blick nach dem Bau lohnt sich deshalb:

```bash
docker run --rm --entrypoint bash <image> -c 'ls -1 /home/frappe/frappe-bench/apps'
```

**Eine neue App aufnehmen:** Eintrag in `apps.json`, pushen, Workflow abwarten, dann auf
der laufenden Site nachinstallieren:

```bash
bench --site erp.nak-studis.de install-app <app>
```

## Warum kein `latest`

`FRAPPE_VERSION` ist auf eine exakte Version gepinnt, und `apps.json` ebenso: dort steht
der ERPNext-Tag, im Workflow der passende Frappe-Tag. Frappe und ERPNext haben eigene
Patch-Nummern — Stand 18.09.2026 laufen `frappe v16.34.0` und `erpnext v16.35.0`
zusammen. Ein floating `latest` hat uns bei Overleaf schon einen Crash-Loop beschert,
weil ein Redeploy still ein neues Image zog und das neue Image plötzlich eine bisher
nicht gesetzte Variable verlangte. Updates werden hier bewusst durch Ändern dieser drei
Stellen ausgelöst — **vorher Backup**, ERPNext migriert das Schema beim Start.

## Deployment

Alle Frappe-Prozesse (backend, websocket, die beiden Queues, scheduler, nginx) laufen als Container
eines Pods, weil sie sich das `sites`-Volume teilen. MariaDB, `redis-cache` und `redis-queue` sind
eigene Deployments; ihre Service-Namen (`db`, `redis-cache`, `redis-queue`) stehen so in
`common_site_config.json`. Eine neue Image-Version: SHA in `apps/erpnext/kustomization.yaml` eintragen,
**vorher Backup**, nach dem Rollout `bench --site erp.nak-studis.de migrate` im backend-Container.

`docker-compose.yaml` beschreibt den früheren Coolify-Stack und dient nur noch als Vorlage für eine
lokale Instanz.

## Backup

Die MariaDB liegt im Volume `db-data`, die Belege im Volume `sites`. **Beides gehört ins
Backup** — bei der Infra-Bestandsaufnahme am 12.09.2026 war fehlendes Backup der
kritischste Befund. Ein Dump allein reicht nicht: ohne `sites` sind alle hochgeladenen
Rechnungen weg.
