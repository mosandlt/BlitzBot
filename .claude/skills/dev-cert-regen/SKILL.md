---
name: dev-cert-regen
description: Erzeuge das selbstsignierte Code-Signing-Cert `blitzbot-dev` neu, falls `security find-identity -p codesigning -v` den Eintrag nicht zeigt. Nur ausführen wenn Cert wirklich fehlt — jedes Re-Cert invalidiert bestehende Accessibility/Input-Monitoring-Permissions.
---

# Dev-Cert `blitzbot-dev` neu erstellen

## Wann ausführen

**Nur wenn das Cert fehlt.** Check:

```bash
security find-identity -p codesigning -v | grep blitzbot-dev
```

Wenn Output leer → Cert fehlt → diesen Skill ausführen. Wenn Output `1 identity` zeigt → Cert ist da, **nichts tun**. Jedes Neu-Ausstellen invalidiert die TCC-Permissions des Users.

## Neu ausstellen

```bash
openssl req -x509 -newkey rsa:2048 -keyout /tmp/k.pem -out /tmp/c.pem -days 3650 -nodes \
  -subj "/CN=blitzbot-dev" -addext "extendedKeyUsage=critical,codeSigning"

openssl pkcs12 -export -inkey /tmp/k.pem -in /tmp/c.pem -out /tmp/c.p12 \
  -passout pass:blitzbot -name "blitzbot-dev" -legacy

security import /tmp/c.p12 -k ~/Library/Keychains/login.keychain-db -P blitzbot \
  -T /usr/bin/codesign -T /usr/bin/security

security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s -k "" \
  ~/Library/Keychains/login.keychain-db

security add-trusted-cert -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db /tmp/c.pem

rm /tmp/k.pem /tmp/c.pem /tmp/c.p12
```

## Was das bewirkt

- **10 Jahre Gültigkeit** (`-days 3650`), selbstsigniert, nur für Code Signing.
- **Private Key in Login-Keychain** mit erlaubten Tools (`codesign`, `security`).
- **Partition-List gesetzt** → kein Passwort-Prompt bei späteren `codesign`-Aufrufen.
- **Trusted für Code Signing** → macOS akzeptiert damit signierte Apps ohne Gatekeeper-Popup.

## Danach

Direkt neu bauen und Permissions erneut erteilen (einmalig):

```bash
./build-app.sh --sign blitzbot-dev
# Dann im System-Settings → Datenschutz → Bedienungshilfen + Input-Monitoring:
# blitzbot.app erneut aktivieren
```

Diese Permission-Re-Grant ist **einmalig** mit dem neuen Cert — alle weiteren Rebuilds überleben die Permission.
