# FRDEVocabMVP

Kleiner iPhone MVP für Französisch und Deutsch.

## Was die App kann

* Vorlage in Französisch oder Deutsch vorsprechen
* Antwort über Mikrofon aufnehmen
* Spracheingabe grob mit der Zielantwort vergleichen
* 20 Wörter und 20 Phrasen pro Richtung

## Voraussetzungen

* Mac mit Xcode
* iPhone
* Apple ID in Xcode eingeloggt

## So startest du die App

1. ZIP entpacken
2. `FRDEVocabMVP.xcodeproj` in Xcode öffnen
3. Links oben als Target `FRDEVocabMVP` wählen
4. Unter `Signing & Capabilities` dein persönliches Team auswählen
5. Bundle Identifier bei Bedarf leicht ändern, zum Beispiel `com.frank.vocabmvp`
6. iPhone anschließen oder als Wireless Device in Xcode verwenden
7. Auf dem iPhone einmal `Developer Mode` aktivieren, falls noch nicht aktiv
8. In Xcode auf Run klicken
9. Beim ersten Start Mikrofon und Spracherkennung erlauben

## Wenn Xcode meckert

### Signing Fehler
Wähle dein Team unter `Signing & Capabilities`.

### Gerät blockiert die App
Auf dem iPhone unter `Settings`, `Privacy & Security`, `Developer Mode` aktivieren. Danach Neustart.

### Untrusted Developer Meldung
Auf dem iPhone unter `Settings`, `General`, `VPN & Device Management` dein Entwicklerprofil bestätigen.

## Nächste sinnvolle Ausbaustufen

* Punkte und Fortschritt speichern
* Eigene Wortlisten importieren
* Bessere Aussprachebewertung statt reinem Textvergleich
* Englisch als dritte Sprache
* Schöneres Card Deck und Session Modus
