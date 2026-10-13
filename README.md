# Familienzeit

Familienplaner fürs iPad: Die Kinder wählen Tag und Tageszeit (morgens, nachmittags, abends) und haken ihre Aufgaben ab. Die Eltern pflegen Kinder, Aufgaben und eigene Termine im Eltern-Bereich (PIN, Start-PIN `0000`).

## Kalender

`.github/workflows/calendar.yml` holt alle 2 Stunden den öffentlichen iCloud-Kalender ab und legt ihn verschlüsselt als `calendar.enc.json` ab. Die App entschlüsselt ihn im Browser mit dem Schlüssel aus dem Link (`#k=…`).

Benötigte Repo-Secrets:

- `ICAL_URL`: öffentlicher iCloud-Kalenderlink (`webcal://…`)
- `FAMILY_KEY`: derselbe Schlüssel wie im App-Link

Der Kalenderlink steht bewusst nicht im Code.

## Daten

Kinder, Aufgaben und Häkchen liegen im Speicher des Geräts. Unter „PIN & Sicherung“ lassen sie sich als Datei sichern und wieder laden.
