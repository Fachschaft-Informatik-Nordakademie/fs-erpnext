# Anmeldung über Authentik (OIDC)

ERPNext bringt mit dem *Social Login Key* einen generischen OpenID-Connect-Client mit.
Authentik pflegt dafür eine eigene Integrationsseite:
https://integrations.goauthentik.io/development/frappe/

Authentik läuft bei uns auf **portal.nak-studis.de** (rammstein, VM 100).

## 1. In Authentik

**Provider** anlegen — Typ *OAuth2/OpenID Provider*:

| Feld | Wert |
|---|---|
| Name | `ERPNext Buchhaltung` |
| Client type | `Confidential` |
| Redirect URI | `https://buchhaltung.nak-inf.de/api/method/frappe.integrations.oauth2_logins.custom/authentik` |
| Signing Key | ein Signing-Zertifikat auswählen (sonst kommt kein `id_token`) |
| Scopes | `openid`, `email`, `profile` |

Client ID und Secret werden dabei erzeugt — beide gleich notieren.

**Application** anlegen, den Provider zuweisen, Slug z. B. `erpnext`.

**Zugriff beschränken:** unter *Policy / Group / User Bindings* eine Bindung auf eine
Gruppe legen, z. B. `buchhaltung`. Ohne diese Bindung darf sich jeder Authentik-Account
einloggen. Der Kreis ist klein: Vorstand, Kassenwart, Kassenprüfer.

## 2. In ERPNext

Anmelden als `Administrator` (Passwort steht in den Coolify-Environment-Variables
unter `ADMIN_PASSWORD`), dann **Integrations → Social Login Key → + New**:

| Feld | Wert |
|---|---|
| Provider Name | `Custom` |
| Custom Base URL | ✅ aktivieren |
| Base URL | `https://portal.nak-studis.de` |
| Client ID | aus Authentik |
| Client Secret | aus Authentik |
| Authorize URL | `/application/o/authorize/` |
| Access Token URL | `/application/o/token/` |
| Redirect URL | `/application/o/userinfo/` |
| API Endpoint | `/application/o/userinfo/` |
| Enable Social Login | ✅ |

Der Slug hinter `.../oauth2_logins.custom/` in der Redirect URI muss zum Namen des
Social Login Key passen — heißt der Key `authentik`, lautet die URI wie oben.

## 3. Prüfen

Abmelden, `https://buchhaltung.nak-inf.de/login` öffnen — dort erscheint ein Button
für den Provider. Login muss nach Authentik und zurück führen.

## Wichtig: der Administrator bleibt

Der lokale `Administrator`-Account ist der Notausgang, wenn Authentik oder die
OIDC-Konfiguration kaputt ist. Er wird **nicht** gelöscht und sein Passwort gehört in
den Vaultwarden der Fachschaft. Erreichbar bleibt er über
`https://buchhaltung.nak-inf.de/login` (Benutzername `Administrator`).

## Rollen

ERPNext-Rollen werden **nicht** aus Authentik übernommen — nach dem ersten Login
bekommt ein Benutzer in ERPNext manuell seine Rolle:

| Person | Rolle in ERPNext |
|---|---|
| Kassenwart | `Accounts Manager` |
| Vorstand (lesend) | `Accounts User` |
| Kassenprüfer | `Auditor` |
