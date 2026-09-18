# erpnext_germany und eu_einvoice

Stand: 18.09.2026. Beide Apps sind installiert (`bench list-apps`):
`frappe 16.34.0`, `erpnext 16.35.0`, `erpnext_germany 16.2.0`, `eu_einvoice 16.2.2`.

## erpnext_germany — was es bringt

| Funktion | Wo |
|---|---|
| **Summen- und Saldenliste** | Berichte → *Summen- und Saldenliste* |
| **Zusammenfassende Meldung** | Berichte → *Zusammenfassende Meldung* (nur bei EU-Auslandsumsätzen relevant) |
| **GDPdU-Export** | Datenträgerüberlassung an die Betriebsprüfung |
| **Registerangaben** | Felder *Register Type / Court / Number* in Company, Customer, Supplier |
| **Lückenlose Nummernkreise** | Löschen ist nur beim jeweils letzten Verkaufsbeleg je Nummernkreis erlaubt |
| **Löschschutz für Anhänge** | Anhänge an **gebuchten** Belegen lassen sich nicht mehr entfernen — genau das, was die GoBD unter Unveränderbarkeit verlangt |
| **USt-IdNr.-Prüfung** | prüft EU-USt-IdNr. von Kunden automatisch alle drei Monate |
| Geschäftsbriefe, Reisekosten, Konfessionen, Krankenkassen | teils abhängig von der HRMS-App (nicht installiert) |

Bereits gesetzt: Company *Studierendenschaft der NORDAKADEMIE e.V.* → **VR 2444, Amtsgericht
Pinneberg** (dieselben Angaben wie im Impressum der Shops).

**Noch offen:** `tax_id` der Company ist leer. Steuernummer bzw. USt-IdNr. eintragen —
ohne die fehlt sie auf jeder Rechnung, und § 14 UStG verlangt sie.

## eu_einvoice — warum das sein muss

Seit **01.01.2025** muss jedes inländische Unternehmen — und der Verein ist als
umsatzsteuerpflichtiger Unternehmer eines — **E-Rechnungen im B2B empfangen und
verarbeiten können**. Betroffen sind bei uns Rechnungen von Lieferanten und an
Sponsoren; Mitgliedsbeiträge (B2C) sind es nicht.

| Funktion | Wo |
|---|---|
| E-Rechnung **empfangen** | *E Invoice Import* — XRechnung/ZUGFeRD hochladen, daraus wird eine Eingangsrechnung |
| E-Rechnung **erstellen** | Felder *E Invoicing* in der Ausgangsrechnung, Profil je Kunde |
| Prüfung | validiert die erzeugte XML gegen das Schema (Feld *E Invoice Is Correct*) |

**Noch offen:** Für erzeugte E-Rechnungen braucht es vollständige Stammdaten — Steuernummer
der Company, Adresse mit Land, und je Kunde ein *E Invoice Profile*. Solange keine einzige
Ausgangsrechnung existiert (Stand heute: null), ist das nicht getestet. Vor der ersten
echten Sponsoring-Rechnung einmal durchspielen.

## Die Apps kommen aus dem Image

Frappe-Apps lassen sich nicht in einen laufenden Container nachlegen. Sie stecken im
Image (`apps.json` → GitHub-Actions-Build, siehe README) und werden auf der bestehenden
Site einmalig aktiviert:

```bash
bench --site erp.nak-studis.de install-app erpnext_germany
bench --site erp.nak-studis.de install-app eu_einvoice
```

Danach die Frappe-Container einmal neu starten, damit Worker und Scheduler die Hooks der
neuen Apps laden.

## Mitgebaut, aber nicht installiert

`erpnext_datev` liegt im Image, ist aber **nicht** auf der Site installiert — die
Entscheidung „UStVA selbst oder Steuerberatung" steht noch aus (siehe
[docs/UMSATZSTEUER.md](UMSATZSTEUER.md)). Bei Bedarf genügt
`bench --site erp.nak-studis.de install-app erpnext_datev`.
