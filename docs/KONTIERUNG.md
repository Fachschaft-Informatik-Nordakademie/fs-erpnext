# Kontierung: Events, Eventreihen, Belege

## Events und Eventreihen = Kostenstellenbaum

ERPNext kennt Kostenstellen als **Baum**. Genau darauf werden die beiden gewünschten
Auswertungsebenen abgebildet:

```
Fachschaft Informatik e.V.
├── Verwaltung
├── Ersti-Woche                 <- Eventreihe
│   ├── Ersti-Party 2026        <- einzelnes Event
│   ├── Campus-Rallye 2026
│   └── Ersti-Frühstück 2026
├── LAN-Party                   <- Eventreihe
│   ├── LAN Sommer 2026
│   └── LAN Winter 2026
└── Merch
```

Anlegen unter **Accounting → Cost Center**. Die Reihen sind *Group*-Knoten, die
einzelnen Events sind Blätter — nur auf Blätter wird gebucht.

**Auswertung:** *Profit and Loss Statement* mit Filter auf eine Kostenstelle.
Auf einem Blatt steht der Gewinn eines Events, auf einem Gruppenknoten summiert
ERPNext die ganze Reihe. Genau die zwei Ebenen, ohne Zusatzarbeit.

Ein Event ist damit **keine** eigene Kontenreihe — die Konten bleiben schlank
(Einnahmen Veranstaltungen, Bewirtung, Raummiete, …), und die Zuordnung passiert über
die Kostenstelle. Das skaliert auch bei 30 Events im Jahr.

## Belege

Jede Buchung (Purchase Invoice, Journal Entry, Payment Entry) hat rechts oben
**Attachments**. Rechnung als PDF oder Foto dort anhängen — der Beleg hängt damit
dauerhaft am Vorgang, nicht in einem separaten Ordner.

Die Anhänge liegen im Docker-Volume `sites`. Das gehört ins Backup — ein reiner
Datenbank-Dump verliert alle Belege.

## Abschreibungen

Wirtschaftsgüter über **800 € netto** (GWG-Grenze, 2026 unverändert) dürfen nicht sofort
als Ausgabe gebucht werden, sondern werden über die Nutzungsdauer abgeschrieben.
In ERPNext: **Assets → Asset**, Anlagegut mit Kaufdatum, Nutzungsdauer und
Abschreibungsmethode anlegen — ERPNext erzeugt daraus den Abschreibungsplan und bucht
die AfA automatisch.

Alles unter 800 € netto: normale Ausgabe, kein Anlagegut.

## Kontenrahmen

ERPNext bringt SKR03/SKR04 mit (`alyf-de/SKR04`). SKR42, der seit 2025 der
Vereins-Kontenrahmen der DATEV ist, ist **nicht** enthalten — er bildet die vier
steuerlichen Tätigkeitsbereiche über Kostenstellen ab. Für diesen Verein ist das
irrelevant, weil er nicht gemeinnützig ist und die Sphärentrennung damit entfällt.
Die Kostenstellen stehen deshalb vollständig für Events zur Verfügung.

Sollte der Verein später die Gemeinnützigkeit anstreben, braucht es eine zweite
Dimension — dann: *Accounting Dimension* „Tätigkeitsbereich" anlegen und die
Kostenstellen weiter für Events nutzen.
