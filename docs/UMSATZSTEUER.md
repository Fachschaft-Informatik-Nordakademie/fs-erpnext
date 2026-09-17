# Umsatzsteuer: beide Wege sind vorbereitet

Der Verein liegt mit über 25.000 € Mitgliedsbeiträgen über der Kleinunternehmergrenze
(§ 19 UStG), ist also umsatzsteuerpflichtig — mit Vorsteuerabzug. Es braucht daher
regelmäßig eine Umsatzsteuer-Voranmeldung (UStVA).

**ERPNext kann kein ELSTER.** Es gibt keine Schnittstelle, die die Voranmeldung direkt
ans Finanzamt schickt. Deshalb sind hier beide gangbaren Wege vorbereitet — die
Entscheidung fällt einmal und lässt sich später ohne Umbau ändern.

## Weg A — Bordbericht, selbst in ELSTER eintragen

Kein Zusatzmodul nötig, funktioniert mit dem Standard-Image.

1. ERPNext → **Accounting → Reports → Tax Detail** für den Voranmeldungszeitraum.
2. Der Bericht listet je Steuervorlage die Bemessungsgrundlage und den Steuerbetrag,
   getrennt nach Ausgangs- und Vorsteuer.
3. Die Beträge in ELSTER-Online in das Formular *Umsatzsteuer-Voranmeldung* übertragen
   (https://www.elster.de).

Aufwand: 10–15 Minuten pro Voranmeldung. Passt, solange der Verein das selbst macht.

## Weg B — DATEV-Export an die Steuerberatung

Dafür braucht es die App `erpnext_datev` (GPLv3, alyf-de), die **nicht** im offiziellen
Image enthalten ist. Sie muss ins Image gebaut werden:

1. GitHub Actions Workflow **build-erpnext-datev-image** in diesem Repo starten
   (Actions → Run workflow). Er baut mit `apps.json` ein Image und pusht es nach
   `ghcr.io/fachschaft-informatik-nordakademie/fs-erpnext:version-16`.
2. In Coolify diese zwei Variablen ändern:
   ```
   FRAPPE_IMAGE=ghcr.io/fachschaft-informatik-nordakademie/fs-erpnext
   FRAPPE_VERSION=version-16
   ```
3. Redeploy. **Achtung:** `create-site` überspringt eine bereits existierende Site — die
   neue App muss dann einmalig nachinstalliert werden:
   ```
   bench --site erp.nak-studis.de install-app erpnext_datev
   ```
   (im `backend`-Container ausführen)
4. In ERPNext unter **Datev Settings** die Beraternummer und Mandantennummer eintragen,
   die die Steuerberatung liefert.
5. Export dann über den Bericht **DATEV** — erzeugt eine ZIP mit Buchungsstapel und
   Stammdaten, die die Kanzlei einliest.

Wird von Anfang an mit DATEV gearbeitet, kann man sich Schritt 3 sparen: dann vor dem
ersten Deploy `INSTALL_APPS=erpnext erpnext_datev` setzen.

## Was in beiden Fällen gilt

- **Steuervorlagen** müssen sauber angelegt sein, sonst stimmt kein Bericht. Nötig sind
  mindestens: Umsatzsteuer 19 %, Umsatzsteuer 7 %, Vorsteuer 19 %, Vorsteuer 7 %.
- **Fristen:** Die Voranmeldung ist bis zum 10. des Folgemonats bzw. Folgequartals fällig,
  mit Dauerfristverlängerung einen Monat später. Welcher Rhythmus gilt, setzt das
  Finanzamt fest.
- **Mitgliedsbeiträge** sind umsatzsteuerlich ein eigenes Thema: die Finanzverwaltung
  unterscheidet echte und unechte Beiträge, EuGH und BFH sehen das anders (zuletzt
  BFH v. 13.11.2025, V R 4/23). Wie die Beiträge des Vereins behandelt werden, ist eine
  Frage an die Steuerberatung — nicht an die Software.
