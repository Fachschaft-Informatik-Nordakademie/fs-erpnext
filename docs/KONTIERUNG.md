# Kontierung: Struktur der Instanz

Stand: 18.09.2026. Company **Studierendenschaft der NORDAKADEMIE e.V.** (Kürzel `StuPa`),
Kontenrahmen **SKR04 mit Kontonummern**, Geschäftsjahr **Kalenderjahr**.

## Eine Company, Fachschaften als Kostenstellen

Der StuPa e.V. ist **eine** Rechtsperson — die Fachschaften wirtschaften eigenständig,
gehören aber offiziell alle dazu. Deshalb: eine Company, ein Kontenrahmen, ein
Jahresabschluss. Die Trennung passiert über den Kostenstellenbaum.

```
Studierendenschaft der NORDAKADEMIE e.V.
├── Main                              (Vorgabe von ERPNext)
└── Fachschaft Informatik
    ├── Veranstaltungen
    │   ├── CineNAK
    │   │   └── CineNAK allgemein
    │   ├── Brettspieltreff
    │   │   └── Brettspieltreff allgemein
    │   └── LAN-Party
    │       └── LAN-Party allgemein
    ├── Laufende Kosten
    │   ├── Server
    │   └── Domains
    └── Team Claudia
```

**Gebucht wird nur auf Blätter.** Gruppenknoten (Eventreihen, „Veranstaltungen",
„Laufende Kosten", „Fachschaft Informatik") summieren nur.

Jede Reihe hat ein Blatt `… allgemein` für Kosten, die zur Reihe gehören, aber zu keinem
einzelnen Termin — etwa ein Beamer für CineNAK oder Spiele für den Brettspieltreff.
**Einzelne Termine kommen als weitere Blätter daneben**, z. B. `LAN-Party Winter 2026`.

**Auswertung:** *Accounting → Profit and Loss Statement*, Filter auf die Kostenstelle.
Auf einem Blatt steht das Ergebnis eines Termins, auf `CineNAK` die ganze Reihe, auf
`Fachschaft Informatik` die komplette Fachschaft, ohne Filter der ganze Verein.

## Laufende Kosten

`Server` und `Domains` sind angelegt, aber ohne Beträge — sie füllen sich, sobald die
ersten echten Rechnungen kommen. Bewusst **kein Budget** hinterlegt: ein Budget von 0 €
würde ERPNext bei jeder Buchung warnen oder blockieren.

Als Aufwandskonto passt `6495 - Wartungskosten f. Hard- und Software`.

## Team Claudia

Mitglieder zahlen **21,04 € pro Monat** für einen Platz in der Claude-Organisation.
Modelliert als normaler Verkaufsvorgang, weil das die einzige Variante ist, bei der
ERPNext offene Posten kennt:

| Objekt | Wert |
|---|---|
| Artikel | `TEAM-CLAUDIA-MONAT` — „Team Claudia - Monatsbeitrag" |
| Preis | 21,04 € (Standard Selling) |
| Ertragskonto | `4400 - Erlöse 19 % USt` |
| Kostenstelle | `Team Claudia` |
| Kundengruppe | `Team Claudia` |
| Abo-Plan | `Team Claudia Monatsbeitrag`, monatlich |
| Steuervorlage | `Team Claudia - 19 Prozent im Preis enthalten` |

**Ein Mitglied aufnehmen:** Customer anlegen (Kundengruppe `Team Claudia`) → Subscription
mit dem Abo-Plan anlegen. ERPNext erzeugt daraus jeden Monat automatisch eine
Ausgangsrechnung.

**Wer noch zahlen muss:** *Accounting → Accounts Receivable*, Filter Kundengruppe
`Team Claudia`. Der Bericht zeigt je Mitglied den offenen Betrag und das Alter der
Forderung. Für Erinnerungen gibt es *Dunning* — das braucht aber ein eingerichtetes
Postfach, siehe offene Punkte im README.

**Offene Frage an die Steuerberatung:** Die 21,04 € sind hier als **Bruttobetrag mit
19 % Umsatzsteuer** angelegt (USt ist im Preis enthalten, Rechnungssumme bleibt exakt
21,04 €). Das Weiterreichen von Softwareplätzen an Mitglieder ist ein Leistungsaustausch
und damit steuerbar. Sollte eure Steuerberatung das anders sehen, ist es ein Ein-Feld-Fix
in der Steuervorlage.

## Umsatzsteuer

ERPNexts deutsche Voreinstellung hatte die Company auf **Kleinunternehmer** gesetzt
(`4185 Erlöse aus Kleinunternehmer § 19 UStG`) und ein falsches Forderungskonto
(`3250 Erhaltene Anzahlungen`). Beides wurde korrigiert auf `4400 - Erlöse 19 % USt`
und `1200 - Forderungen aus Lieferungen und Leistungen`.

Das ist wichtig: Der Verein liegt mit über 25.000 € Mitgliedsbeiträgen **über** der
Kleinunternehmergrenze. Wäre die Vorgabe geblieben, wären alle Erlöse auf dem
Kleinunternehmerkonto gelandet und die Voranmeldung wäre unbrauchbar gewesen.

Steuerkonten aus dem SKR04: `3806` USt 19 %, `3801` USt 7 %, `1406` Vorsteuer 19 %,
`1401` Vorsteuer 7 %.

## Abschreibungen

Wirtschaftsgüter über **800 € netto** (GWG-Grenze, 2026 unverändert) werden nicht sofort
als Ausgabe gebucht, sondern über **Assets → Asset** als Anlagegut mit Nutzungsdauer
erfasst. ERPNext erzeugt daraus den Abschreibungsplan und bucht die AfA automatisch —
dafür muss der Scheduler laufen, er ist aktiviert.

Alles darunter: normale Ausgabe.
