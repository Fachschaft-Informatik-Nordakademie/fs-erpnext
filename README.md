# ERPNext — Buchhaltung der Fachschaft Informatik e.V.

Selbstgehostete Vereinsbuchhaltung auf Basis von [ERPNext](https://erpnext.com) (GPLv3).
Deployment über Coolify, Quelle ist dieses Repository.

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
| Coolify | https://coolify.nak-inf.de |
| Projekt | **Fachschaften** → Environment `production` |
| Server | **slipknot** (VM 200, 10.0.0.200) — dort laufen auch die beiden Firefly-III-Instanzen |
| Host-Port | `5010` (belegt auf slipknot: 3000, 5006, 5007, 5678, 8000, 9000, 9001) |
| Ingress | NPMplus auf rammstein (10.0.0.100) → `10.0.0.200:5010` |
| Domain | `erp.nak-studis.de` |

Routing läuft wie bei den anderen Diensten auf slipknot über NPMplus, nicht über
Coolifys Traefik — deshalb veröffentlicht der `frontend`-Service seinen Port auf den Host.

## Struktur

```
docker-compose.yaml   der komplette Stack (eine Datei, Coolify-tauglich)
.env.example          alle Variablen mit Erklärung — Werte selbst setzen in Coolify
apps.json             welche Apps ins Image gebaut werden (gepinnte Versionen)
.github/workflows/    baut das Image nach ghcr.io
docs/AUTHENTIK.md     SSO-Einrichtung
docs/MAIL.md          Mailversand über erp@nak-studis.de
docs/UMSATZSTEUER.md  UStVA: Bordbericht-Weg und DATEV-Weg
docs/KONTIERUNG.md    Kontenrahmen, Kostenstellen, Events und Eventreihen
```

## Der `create-site`-Trick

ERPNext braucht einen einmaligen Init-Schritt (`bench new-site`), der in Coolify sonst
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

## Drei Fallen, die beim Aufbau Zeit gekostet haben

1. **`${VAR:?meldung}` niemals in der Compose-Datei.** Coolify parst die Datei beim
   Anlegen der Ressource und übernimmt die *Fehlermeldung als Default-Wert*. Ergebnis
   war eine Site namens „SITE_NAME fehlt". Pflichtfelder prüft jetzt `create-site`.
2. **Das Docker-Netz `coolify` muss auf dem Zielserver existieren.** Coolify-*Services*
   bekommen je ein eigenes Netz, Coolify-*Applications* nutzen das Destination-Netz
   `coolify`. Auf slipknot gab es das nie → `network coolify not found`.
   Fix: `docker network create --attachable coolify`.
3. **Coolify-Env-API:** `POST /applications/{uuid}/envs` mit `is_literal`/`is_preview`/
   `is_build_time` gibt 422 — nur `{key, value}` senden. PATCH aktualisiert, POST legt
   sonst stille Duplikate an.

## Das Image

Die Instanz läuft **nicht** auf `frappe/erpnext`, sondern auf einem selbstgebauten Image
`ghcr.io/fachschaft-informatik-nordakademie/fs-erpnext`. Grund: ERPNext allein reicht
nicht, es braucht drei Zusatz-Apps von [ALYF](https://github.com/alyf-de) —
`erpnext_germany` (deutsche Pflichten), `eu_einvoice` (XRechnung/ZUGFeRD) und
`erpnext_datev` (Export an die Steuerberatung). Frappe-Apps lassen sich nicht nachträglich
in einen laufenden Container legen, sie müssen ins Image.

Gebaut wird über `.github/workflows/build-image.yml` — der Workflow läuft automatisch bei
jeder Änderung an `apps.json` und ist auch von Hand startbar. Das Ergebnis bekommt zwei
Tags: die ERPNext-Version (`v16.35.0`) und den Commit-SHA.

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

1. In Coolify: Projekt **Fachschaften** → `production` → **+ New** → **Public Repository**
2. Repo `https://github.com/Fachschaft-Informatik-Nordakademie/fs-erpnext`, Branch `main`
3. Build Pack: **Docker Compose**, Compose-Datei `docker-compose.yaml`
4. Server: **slipknot**
5. Environment Variables aus `.env.example` setzen (Passwörter frisch erzeugen:
   `openssl rand -base64 32`)
6. **Automatic Deployment** aktivieren — Coolify legt den GitHub-Webhook an und zieht
   jeden Push auf `main`
7. Deploy. Der erste Start dauert einige Minuten (`create-site` legt die Datenbank an).

Danach: NPMplus-Proxy-Host auf `10.0.0.200:5010`, dann [docs/AUTHENTIK.md](docs/AUTHENTIK.md).

## Backup

Die MariaDB liegt im Volume `db-data`, die Belege im Volume `sites`. **Beides gehört ins
Backup** — bei der Infra-Bestandsaufnahme am 12.09.2026 war fehlendes Backup der
kritischste Befund. Ein Dump allein reicht nicht: ohne `sites` sind alle hochgeladenen
Rechnungen weg.
