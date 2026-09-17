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

**Grant Types nicht vergessen.** Unter *Advanced protocol settings* muss
`authorization_code` (und sinnvollerweise `refresh_token`) in **Grant types** stehen.
Authentik 2026.8 pflegt diese Liste pro Provider, und beim Anlegen über die API bleibt
sie **leer** — die Anmeldung scheitert dann mit `invalid_request` /
„The request is otherwise malformed", was im ERPNext-Callback als HTTP 500 ankommt.
Im Authentik-Log steht der eigentliche Grund: `Invalid grant_type for provider`.

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

## 3. Benutzer anlegen

Zwei Dinge müssen zusammenpassen:

1. Der Account ist in Authentik **Mitglied der Gruppe `buchhaltung`** — sonst blockt
   das Policy-Binding den Zugriff auf die Application.
2. In ERPNext existiert ein **User mit derselben E-Mail-Adresse**. Frappe ordnet den
   SSO-Login über die Mailadresse aus dem `userinfo`-Endpoint zu. Der Provider läuft
   deshalb mit `sub_mode = user_email`.

Neue Person: in Authentik der Gruppe hinzufügen, in ERPNext unter **Users** anlegen
(User Type `System User`, Rolle siehe unten), fertig — beim ersten Login wird nichts
weiter gefragt.

## 4. Prüfen

Abmelden, `https://buchhaltung.nak-inf.de/login` öffnen — dort erscheint ein Button
für den Provider. Login muss nach Authentik und zurück führen.

## Nur SSO, kein Passwort-Login

In den System Settings ist gesetzt:

```
disable_user_pass_login = 1   # kein Benutzername/Passwort mehr
login_with_email_link   = 0   # kein Magic-Link-Login
```

Die Login-Seite bietet damit ausschließlich den Authentik-Button. Das ist Absicht:
ein zweiter, schwächerer Anmeldeweg neben dem SSO ist genau die Lücke, die man sich
sonst offen lässt.

**Preis dafür — der Notausgang liegt jetzt auf der Shell.** Wenn Authentik ausfällt
oder die OIDC-Konfiguration kaputtgeht, kommt *niemand* mehr über den Browser rein,
auch der `Administrator` nicht. Wiederherstellung dann über den Container:

```bash
# auf slipknot (10.0.0.200), Root-Shell dort ist fish -> Skript ueber bash -s
CT=$(docker ps --filter name=backend-vlypchwxzmqzlzyznd3ovf0m -q | head -1)
docker exec "$CT" bench --site buchhaltung.nak-inf.de \
  set-config -p disable_user_pass_login 0
docker exec "$CT" bench --site buchhaltung.nak-inf.de set-admin-password '<neues-passwort>'
```

Danach ist der Passwort-Login wieder da und der `Administrator` nutzbar. Sein Passwort
steht in den Coolify-Environment-Variables unter `ADMIN_PASSWORD` und gehört zusätzlich
in den Vaultwarden der Fachschaft.

## Rollen

ERPNext-Rollen werden **nicht** aus Authentik übernommen — nach dem ersten Login
bekommt ein Benutzer in ERPNext manuell seine Rolle:

| Person | Rolle in ERPNext |
|---|---|
| Kassenwart | `Accounts Manager` |
| Vorstand (lesend) | `Accounts User` |
| Kassenprüfer | `Auditor` |
