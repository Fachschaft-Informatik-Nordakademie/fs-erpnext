# Mailversand aus ERPNext

Stand: 18.09.2026. ERPNext verschickt Rechnungen, Mahnungen und Benachrichtigungen
über das Funktionspostfach **`erp@nak-studis.de`** auf der Mailcow-Instanz
`mx.stupanak.de` (VM `acdc`, 10.0.0.202).

## Warum ein eigenes Postfach

Der Versand läuft nicht über `noreply@nak-inf.de`, weil Rechnungen und Mahnungen
beantwortet werden — das Postfach muss also gelesen werden können. Es hängt
deshalb an derselben Zugriffsmechanik wie alle anderen Gruppenpostfächer: wer in
Authentik in der Gruppe **Fachschaft Informatik Vorstand** ist, sieht den Ordner
in SOGo und kann als `erp@nak-studis.de` antworten.

## Wie das Postfach angebunden ist

| | |
|---|---|
| Postfach | `erp@nak-studis.de`, Anzeigename `ERPNext Buchhaltung (erp@nak-studis.de)` |
| Authsource | `mailcow` (lokales Passwort) — **nicht** `generic-oidc`, weil ERPNext sich per SMTP anmelden muss |
| Passwort | Vaultwarden der Fachschaft, Eintrag `Mailcow SMTP erp@nak-studis.de` |
| Zugriff für Menschen | über `authentik-mailcow-acl-sync.py` auf `acdc` — die Adresse steht in `MAPPINGS` unter `Vorstand-INF` |
| Quota | 1 GB |

Der Sync-Cron (alle 15 Minuten) setzt für jedes Vorstandsmitglied drei Dinge:
Dovecot-ACL auf alle Ordner, `sender_acl` („Senden als"), und die Adresse als
SOGo-Absenderidentität. Wer aus dem Vorstand ausscheidet, verliert alle drei
automatisch. **Hier ist nichts von Hand zu pflegen** — neue Vorstände bekommen
den Zugriff durch ihre Authentik-Gruppe.

## Netzwerkweg

`mx.stupanak.de` löst öffentlich auf 94.130.19.169 auf. mango kann kein
NAT-Hairpin, ein Container auf slipknot würde also ins Leere laufen. Deshalb
steht in `docker-compose.yaml`:

```yaml
extra_hosts:
  - "mx.stupanak.de:${MAILCOW_LAN_IP:-10.0.0.202}"
```

Der **Hostname bleibt stehen**, nur das Ziel ist die LAN-Adresse. Das ist
wichtig, weil Python ab 3.12 bei `starttls()` das Zertifikat gegen den
verwendeten Hostnamen prüft — und das Mailcow-Zertifikat trägt `mx.stupanak.de`.
Mit einer nackten IP im Feld „Email Server" würde der Versand an der
Zertifikatsprüfung scheitern.

## Einstellungen in ERPNext

*Settings → Email Account →* `ERPNext Versand`:

| Feld | Wert |
|---|---|
| Email Address | `erp@nak-studis.de` |
| Login ID | `erp@nak-studis.de` |
| Email Server (SMTP) | `mx.stupanak.de` |
| SMTP-Port | `587`, STARTTLS (`use_tls`) |
| Default Outgoing | ja |
| Always use Account's Email Address as Sender | ja |
| Incoming (IMAP) | aus — siehe unten |

IMAP ist bewusst **nicht** aktiviert. Würde ERPNext das Postfach abrufen, würde
es Mails als gelesen markieren und aus dem Posteingang in `Communication`
ziehen; der Vorstand sieht in SOGo dann nichts mehr. Antworten auf Rechnungen
werden also in SOGo gelesen, nicht in ERPNext.

## Grenzen

`nak-studis.de` hat MX, SPF (`v=spf1 mx ~all`) und DMARC (`p=quarantine`).
Zustellung nach außen funktioniert damit grundsätzlich — die Reputation der
ausgehenden IP ist aber ein eigenes Thema (siehe Mailcow-Doku der Fachschaft,
Stichwort T-Online-Blockade). Vor dem ersten echten Rechnungslauf an Mitglieder
sollte eine Testmail an eine externe Adresse geprüft werden.
