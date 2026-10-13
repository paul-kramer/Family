# Familienzeit

Familienplaner fürs iPad: Die Kinder wählen Tag und Tageszeit (morgens, nachmittags, abends) und haken ihre Aufgaben ab. Die Eltern pflegen Kinder, Aufgaben und eigene Termine im Eltern-Bereich (PIN, Start-PIN `0000`).

## Kalender

`.github/workflows/calendar.yml` holt alle 2 Stunden den öffentlichen iCloud-Kalender ab und legt ihn verschlüsselt als `calendar.enc.json` ab. Die App entschlüsselt ihn im Browser mit dem Schlüssel aus dem Link (`#k=…`).

Benötigte Repo-Secrets:

- `ICAL_URL`: öffentlicher iCloud-Kalenderlink (`webcal://…`)
- `FAMILY_KEY`: derselbe Schlüssel wie im App-Link

Der Kalenderlink steht bewusst nicht im Code.

## Daten (Supabase)

Kinder, Aufgaben, PIN und Häkchen liegen in einer Supabase-Datenbank und sind auf allen Geräten mit dem Link sofort gleich.

Einrichtung: Projekt auf supabase.com anlegen (Region Frankfurt), `supabase/schema.sql` im SQL Editor ausführen, dann Project URL und anon-Schlüssel in `config.js` eintragen.

Die Tabellen sind für den öffentlichen Schlüssel gesperrt. Lesen und Schreiben geht nur über Funktionen, die den Familien-Schlüssel aus dem Link (`#k=…`) verlangen; gespeichert ist davon nur die SHA-256-Prüfsumme. Ohne Verbindung arbeitet die App mit dem Stand auf dem Gerät weiter. Unter „PIN & Sicherung“ lässt sich alles zusätzlich als Datei sichern.

## iOS-App (ios/)

Native SwiftUI-App für iPad und iPhone (ab iOS 17). Sie liest die Termine direkt aus den Kalendern des Geräts, auch aus iCloud. Dafür braucht sie weder den öffentlichen Kalender-Link noch die GitHub-Action.

### Auf das iPad bringen

1. Am Mac Xcode aus dem App Store installieren (Version 16 oder neuer).
2. Repo herunterladen: in Xcode „Clone Git Repository…“ mit `https://github.com/paul-kramer/Family` oder per Terminal `git clone`.
3. `ios/Familienzeit.xcodeproj` öffnen.
4. Links das Projekt „Familienzeit“ anklicken → Target „Familienzeit“ → Reiter „Signing & Capabilities“ → bei „Team“ deine Apple-ID wählen (ggf. über „Add an Account…“ anmelden). Falls Xcode den Bundle Identifier ablehnt, hinten etwas anhängen, z. B. `de.paulkramer.familienzeit2`.
5. iPad per Kabel anschließen, entsperren und „Diesem Computer vertrauen“ bestätigen.
6. Auf dem iPad: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus einschalten (iPad startet neu).
7. In Xcode oben das iPad als Ziel wählen und auf ▶ klicken.
8. Beim ersten Start auf dem iPad: Einstellungen → Allgemein → VPN & Geräteverwaltung → deiner Apple-ID vertrauen.
9. Beim Start der App den Kalenderzugriff erlauben.

Mit einer kostenlosen Apple-ID läuft die App 7 Tage und muss dann über Xcode neu installiert werden (Schritt 7). Mit dem Apple Developer Program (99 €/Jahr) gilt sie ein Jahr.

### Kinder auf die App beschränken

Einstellungen → Bedienungshilfen → Geführter Zugriff einschalten. In der App dreimal die obere Taste drücken, um sie zu sperren.

### Daten aus der Web-Version übernehmen

Web-Version: Eltern → PIN & Sicherung → „Sicherung speichern“. iOS-App: Eltern → PIN & Sicherung → „Sicherung laden“.
