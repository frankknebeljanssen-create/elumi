# Elumi: Design-Review- und Produkt-Briefing

## 1. Kurzüberblick

Elumi ist eine iOS-Lernapp für Französisch-Deutsch. Der Kern der App ist nicht nur klassisches Vokabellernen, sondern das Umwandeln realer Inhalte in Lernmaterial:

- gescannte Vokabellisten
- fotografierte Lehrbuchseiten
- freie Texte wie Plakate, Aushänge, Magazinseiten oder gemischte Inhalte
- eigenes Wörterbuch als lokaler Wissenspool

Die App verbindet vier Dinge:

1. Inhalt erfassen
2. Inhalt aufbereiten
3. daraus Lernkarten/Lernmodi erzeugen
4. Fortschritt spielerisch sichtbar machen

Die App ist visuell als Unterwasser-/Elumi-Welt gedacht: Axolotl-Maskottchen, Wasserstimmung, kleine Snack-Wesen, weiche Animationen, dunklere Flächen, freundlicher Lerncharakter statt nüchterner Utility-App.

## 2. Produktziel

Elumi soll aus echten, fotografierten oder gescannten Französisch-Inhalten schnell Lerninhalt machen, den Nutzerinnen und Nutzer direkt weitertrainieren können.

Wichtig ist:

- Französisch ist die Quellsprache, Deutsch die Zielsprache
- Inhalte sollen nicht nur erkannt, sondern sinnvoll in Lernobjekte übersetzt werden
- bei Vokabellisten anders als bei freiem Text
- der Review-Schritt ist zentral, damit Nutzer das Ergebnis prüfen und korrigieren können
- langfristig soll KI schwierige Layouts und gemischte Texte zuverlässiger auflösen als reine OCR

## 3. Zielgruppe

Primär:

- deutschsprachige Französischlernende
- Schule, Selbstlernen, Nachhilfe, Lehrbuchbegleitung

Besonders relevant:

- Nutzer fotografieren Inhalte spontan mit dem Handy
- Nutzer wollen nicht manuell tippen
- Nutzer brauchen visuelle Sicherheit: Was wurde erkannt? Was wird importiert? Was ist Lernstoff?

## 4. Plattform und Tech Specs

### Plattform

- iOS-App
- SwiftUI-App mit `WindowGroup`

### Tech Stack

- `SwiftUI` für UI
- `AVFoundation` für Audioausgabe
- `Speech` für Spracherkennung
- `Vision` für OCR
- `VisionKit` für Dokumentenscan/Kamera
- `UIKit` für Bild- und Kamera-Interop
- `NaturalLanguage` für sprachliche Heuristiken, u. a. bei Freitext
- `CoreImage` / Bildvorbereitung
- `SQLite3` für lokales Wörterbuch / Knowledge Pool
- OpenAI Responses API für KI-gestützte Analyse

### Architekturstand heute

Die App ist funktional schon recht weit, aber die Codebasis ist nur teilweise modularisiert:

- viel Produktlogik liegt noch in einer großen Datei:
  - `/Users/frankknebeljanssen/Documents/New project/VocabMVP/FRDEVocabMVP/ContentView.swift`
- die Scan-Architektur wurde bereits in separate Bausteine ausgelagert:
  - `/Users/frankknebeljanssen/Documents/New project/VocabMVP/FRDEVocabMVP/ScanModels.swift`
  - `/Users/frankknebeljanssen/Documents/New project/VocabMVP/FRDEVocabMVP/ScanProviders.swift`
  - `/Users/frankknebeljanssen/Documents/New project/VocabMVP/FRDEVocabMVP/ScanEngine.swift`
  - `/Users/frankknebeljanssen/Documents/New project/VocabMVP/FRDEVocabMVP/ScanClassifier.swift`
  - `/Users/frankknebeljanssen/Documents/New project/VocabMVP/FRDEVocabMVP/ScanReviewMapping.swift`
  - `/Users/frankknebeljanssen/Documents/New project/VocabMVP/FRDEVocabMVP/ScanAIProvider.swift`
- Design Tokens / UI-Grundbausteine liegen in:
  - `/Users/frankknebeljanssen/Documents/New project/VocabMVP/FRDEVocabMVP/DesignSystem.swift`

### Persistenz

- App-Zustände, Gamification-Werte und UI-Präferenzen über `AppStorage` / `UserDefaults`
- eigene Listen und Sessions lokal gespeichert
- kuratierter FR-DE-Knowledge-Pool lokal gebündelt als SQLite
- zusätzlicher großer FreeDict-Supplement-Pool ebenfalls lokal gebündelt als SQLite

### Wörterbuch-/Knowledge-Pool

Die App arbeitet lokal mit zwei Wissensschichten:

1. kuratierter interner FR-DE-Pool
2. großer FreeDict-Supplement-Pool

Ziele dieses Pools:

- Wörterbuchsuche
- OCR-/Scan-Nachkorrektur
- bessere Groß-/Kleinschreibung
- Artikel-/Gender-Unterstützung
- bessere FR-DE / DE-FR-Zuordnung

### KI-Scan

Aktueller Ansatz:

- GPT-first
- OCR als Fallback

Technisch:

- OpenAI Responses API
- Standardmodell aktuell `gpt-5-mini`
- API-Key über `OPENAI_API_KEY` in der Xcode-Umgebung
- Bild aktuell mit höherem Detail an GPT
- Antwort über striktes JSON-Schema

## 5. Kernmodule der App

### 5.1 Salut / Home

Zentrale Startseite mit Modulkarten.

Aktuelle Hauptmodule:

- Trainieren
- Karteikarten
- Quiz
- Scan
- Wörterbuch
- Listen

Gestaltungsziel:

- klar, freundlich, warm
- modulare Karten
- Unterwasserwelt / Elumi-Charakter
- Footer-Navigation als konstante Basis

### 5.2 Scan

Wichtigstes Produktmodul.

Zwei Modi:

1. Vokabelliste
2. Freier Text

Einstieg:

- Aufnahme
- Foto

Danach:

- Bildvorschau
- Analyse
- Review
- Import

### 5.3 Wörterbuch

Kein vollständiger Dump der Einträge, sondern suchzentriert.

Aktueller Ansatz:

- oben nur Suchfeld
- Treffer erscheinen erst nach Eingabe
- Treffer sind gruppiert und gebündelt
- Detailkarte zeigt Bedeutungen, ggf. Wortart, Gender, Varianten

### 5.4 Trainieren

Sprech-/Hör- und Reaktionsmodus.

Nutzer wählen:

- Quelle / Liste
- ggf. Wörterbuch als Lernquelle
- Niveau

Dann:

- Prompt
- Antwort per Sprache / Text
- direktes Feedback

### 5.5 Karteikarten

Klassischer Stapelmodus mit Flip-Interaktion.

Wichtig:

- Vorder- / Rückseite
- Lösung / Zurück / Überspringen
- Sprach- und Texteingabe
- Review-Feeling, aber leichter und spielerischer als im Quiz

### 5.6 Quiz

Strukturiertes Testformat.

Wichtig:

- 5 oder 10 Fragen
- Ergebnis-Screen
- Belohnungssystem / Beute / XP

### 5.7 Listen

Verwaltung eigener Listen.

Möglichkeiten:

- eigene Listen anlegen
- umbenennen
- Einträge editieren
- aus Scan importieren
- Testlisten und Sammellisten nutzen

### 5.8 Sammlung / Gamification

Elumi sammelt nicht mehr Herzen, sondern Beute.

Aktuelle Beutearten:

- Würmchen
- Wasserflöhe
- Algenkugeln

Weitere Spielsysteme:

- XP
- Level
- Streak
- Belohnungen nach Quiz und Aktivität

### 5.9 Einstellungen / Konto / Info

- Ton an/aus
- Konto / Vorname
- Info / Hilfe

## 6. Haupt-Workflow: Vokabellisten scannen

### Ziel

Eine fotografierte oder gescannte Vokabelliste in editierbare Lernkarten umwandeln.

### Soll-Workflow

1. Nutzer wählt `Scan`
2. Nutzer wählt `Vokabelliste`
3. Nutzer wählt `Foto` oder `Aufnahme`
4. Bild wird vorbereitet
5. Analyse startet
6. erkannte Paare erscheinen im Review
7. Nutzer korrigiert bei Bedarf
8. Nutzer vergibt Listenname und Ordner
9. Import
10. Inhalt steht danach in Listen / Training / Karteikarten / Quiz zur Verfügung

### Verarbeitung intern

1. Bildvorbereitung
2. OCR- oder GPT-Analyse
3. Dokumentklassifikation
4. Paarbildung / Strukturierung
5. Mapping in Review-Modell
6. manuelle Korrektur
7. Import in `VocabularyItem`-Logik

### Wichtige UX-Anforderungen

- Nutzer muss erkennen, ob GPT oder OCR läuft
- Nutzer braucht sofort sichtbares Ergebnis
- Review muss editierbar und verlässlich sein
- Satzzeichen, Namen, Artikel, Gender dürfen nicht unnötig zerstört werden
- Meta-Marker aus Lehrbüchern müssen raus

## 7. Haupt-Workflow: Freien Text scannen

Freier Text ist bewusst **kein** Vokabellisten-Workflow.

### Ziel

Ein freier gescannter Inhalt, z. B. ein Plakat, Aushang oder Textausschnitt, soll in lernbare Einheiten überführt werden.

### Nicht das Ziel

- jedes Wort 1:1 importieren
- triviale Funktionswörter behalten
- rohe OCR-Zeilen als Lernkarten importieren

### Gewünschte Aufbereitung

Der Review soll freie Texte in vier Buckets gliedern:

1. `Text erkannt`
2. `Verben`
3. `Phrasen`
4. `Grammatik`

### Bedeutung der Buckets

#### Text erkannt

- Kontext
- zeigt den erkannten Inhalt
- soll helfen, den Ursprung zu verstehen
- wird nicht als normale Lernkarte importiert

#### Verben

- nur sinnvolle Verben
- keine trivialen Füllformen wie `je`, `tu`, `et`, `est`
- Fokus auf lernrelevante Verben

#### Phrasen

- sinnvolle Wendungen
- Schilder-/Aushangsprache
- höfliche Formeln
- gebräuchliche Satzbausteine

#### Grammatik

- kurze, direkt lernbare Muster
- z. B.:
  - `merci de + infinitif`
  - `pas de + nomen`
  - `c'est`
  - Frageformen
  - Elision

### Beispiel Plakat / Aushang

Für ein Poster wie:

- `Bienvenue`
- `Merci de respecter le silence`
- `Pas de visite pendant les offices`

soll die App eher sinnvolle Lernobjekte ableiten und nicht Uhrzeiten, Wochentage oder Meta-Zeilen priorisieren.

## 8. Scan-Architektur

### Aktuelle Struktur

#### `ScanAnalysisEngine`

Zentrale Orchestrierung.

- nimmt `ScanRequest`
- ruft Primärprovider auf
- prüft Qualität / Dokumenttyp
- zieht Fallback-Provider hinzu
- gibt bestes Ergebnis zurück

#### `OCRScanProvider`

Lokaler OCR-Pfad.

- Vision OCR
- mehrere Pässe
- Fast-Pass
- Enhanced Fallback
- Analyse und Scoring

#### `OpenAIResponsesScanAIClient`

KI-Pfad.

- OpenAI Responses API
- Bild + Prompt
- JSON-Schema
- strukturierte Extraktion

#### `ScanDocumentClassifier`

Unterscheidet u. a.:

- `vocabularyList`
- `textbookTable`
- `freeText`
- `mixedLayout`
- `poster`
- `cover`
- `unknown`

#### `ScanReviewMapping`

Mappt Engine-/Provider-Output in das UI-Modell des Reviews.

### Warum diese Architektur wichtig ist

Sie erlaubt:

- OCR und KI nebeneinander
- schrittweisen Ausbau
- späteren Claude-/anderen Fallback
- keinen weiteren Architekturballast in `ContentView.swift`

## 9. Aktuelle UX- und Designprinzipien

### Visuelle Leitidee

- Elumi als sympathische Figur
- Unterwasserwelt
- leichte Bewegung, aber nicht Spielzeug-chaotisch
- dunklere Hintergründe mit klaren Kontrasten
- freundliche, runde Formsprache

### Navigation

- starker Footer als konstantes Element
- Modulseiten sollen sich wie Teile einer zusammenhängenden Welt anfühlen

### Design-System

Es gibt zentrale Farben, Spacing, Radius- und Surface-Bausteine in:

- `/Users/frankknebeljanssen/Documents/New project/VocabMVP/FRDEVocabMVP/DesignSystem.swift`

Wichtig:

- CTA-Farben bewusst sparsam
- Lernmodule farblich gruppieren
- Hilfs-/Utility-Module anders gruppieren

## 10. Aktueller Produktstand: Was schon funktioniert

- Footer-basierte Navigation
- Splash mit Elumi und Unterwasser-Animationen
- Scan aus Kamera und Foto
- GPT-first-Scan mit OCR-Fallback
- Wörterbuch mit Suchmodus statt Voll-Listung
- lokale Listenverwaltung
- Trainieren
- Karteikarten
- Quiz
- Gamification mit Beute / XP / Level / Streak
- Free-Text-Workflow mit vier Buckets
- Wörterbuch mit lokalem SQLite-Pool und FreeDict-Supplement

## 11. Aktuelle Pain Points / offene Baustellen

Diese Punkte sind wichtig für jedes ehrliche Review:

### 11.1 Scan-Zuverlässigkeit

- OCR kann bei Lehrbuchseiten durch Lautschrift und Meta-Marker gestört werden
- Satzzeichen wie `?`, `!`, `.` sind noch eine kritische Stelle
- Platzhalter vs. konkrete Namen müssen sauber unterschieden werden
- GPT ist deutlich besser, aber teurer und langsamer

### 11.2 Lehrbuch-Meta

Marker wie:

- `fam.`
- `adj. inv.`
- Lautschrift in `[...]`

dürfen nicht als Vokabeln interpretiert werden.

### 11.3 Wörterbuchqualität

- nicht jede Gender-/Artikelinformation ist vollständig
- offene Datenquellen sind nicht überall lexikografisch perfekt
- Gruppierung und Dubletten müssen sauber bleiben

### 11.4 Architektur

- `ContentView.swift` ist weiterhin sehr groß
- Kernlogik ist teilweise schon extrahiert, aber noch nicht vollständig
- mittelfristig wären weitere Domänen-Dateien sinnvoll

### 11.5 Performance

- GPT kann lange dauern
- OCR hatte zeitweise Memory-Probleme
- Wörterbuchsuche und Scan müssen gefühlt schnell bleiben

### 11.6 Produktentscheidungen

Noch offen oder review-würdig:

- Wie sichtbar soll die Technik sein: GPT/OCR-Label oder nicht?
- Wie viel Review braucht freie Textanalyse?
- Wie stark soll Gamification präsent sein?
- Wie stark soll Wörterbuch vs. Lernmodus getrennt sein?

## 12. Was ein guter Design Review bewerten sollte

Bitte nicht nur visuell, sondern als Produkt- und UX-Review bewerten:

### Informationsarchitektur

- Ist die Aufteilung der Module logisch?
- Versteht man schnell den Unterschied zwischen Scan, Wörterbuch, Listen und Lernmodi?

### Scan UX

- Ist der Flow vom Bild bis zum Review verständlich?
- Ist die Trennung `Vokabelliste` vs. `Freier Text` klar?
- Sind Status, Vertrauen und Korrigierbarkeit ausreichend?

### Wörterbuch UX

- Ist Suchmodus sinnvoller als Vollanzeige?
- Sind Trefferlisten und Detailkarten klar genug?
- Reichen die Metadaten für Lernzwecke?

### Lernmodi

- Fühlen sich Training, Karteikarten und Quiz konsistent, aber klar unterschiedlich an?
- Sind Rückmeldungen motivierend und verständlich?

### Gamification

- Unterstützt sie das Lernen oder lenkt sie ab?
- Ist der Einsatz der Beute-Wesen stimmig?

### Design-System

- Wirkt die App visuell aus einem Guss?
- Sind Farben sinnvoll gruppiert?
- Ist der Footer wirklich stark genug als konstantes Navigations-Element?

### Motion / Character

- Passt die Unterwasserwelt?
- Sind Splash, Maskottchen und kleine Ambient-Animationen sinnvoll eingebettet?
- Wirken sie hochwertig oder eher ablenkend?

## 13. Was ein guter Tech-/Produkt-Feedback-Review bewerten sollte

- Ist die Scan-Architektur tragfähig?
- Ist GPT-first + OCR-Fallback die richtige Strategie?
- Ist das Review-Modell robust genug als gemeinsame Mitte?
- Ist die Trennung zwischen Vokabelliste und freiem Text gut gelöst?
- Sind Wörterbuch und Scan ausreichend an denselben Knowledge Pool gekoppelt?
- Wo sollte man als Nächstes weiter modularisieren?

## 14. Konkrete Review-Fragen an eine KI

Folgende Fragen sind für Elumi besonders wertvoll:

1. Ist die Produktstruktur klar und verständlich?
2. Wo ist die App visuell stark, wo inkonsistent?
3. Welche Teile fühlen sich schon wie ein fertiges Produkt an, welche noch wie ein Prototyp?
4. Ist der Scan-Workflow vertrauenswürdig genug?
5. Ist die Trennung zwischen `Vokabelliste` und `Freier Text` sinnvoll und klar?
6. Ist das Wörterbuch so aufgebaut, wie Nutzer es wirklich verwenden würden?
7. Welche 3 UX-Probleme würden die Nutzung aktuell am stärksten bremsen?
8. Welche 3 Design-Verbesserungen hätten die größte Wirkung?
9. Welche 3 technischen/architektonischen Risiken sind mittelfristig am wichtigsten?
10. Welche Funktionen fehlen für ein starkes MVP noch wirklich?

## 15. Prompt, den man direkt an eine KI geben kann

Du kannst einer KI diesen Text plus die Screenshots oder den aktuellen Code geben und dann z. B. diesen Prompt davor setzen:

> Lies das folgende Briefing zu Elumi vollständig. Beurteile die App als Produkt-, UX-, Design- und Architektur-Review. Gib mir:
> 1. eine kurze Einordnung des Produkts,
> 2. die 5 wichtigsten Stärken,
> 3. die 5 wichtigsten Schwächen,
> 4. konkrete Verbesserungsvorschläge für Navigation, Scan-UX, Wörterbuch, Lernmodi und Gamification,
> 5. die wichtigsten technischen Risiken,
> 6. eine klare Priorisierung: Was sollte vor einem MVP-Launch unbedingt noch verbessert werden?
> Bitte antworte konkret, kritisch und lösungsorientiert, nicht nur allgemein.

## 16. Kurzfazit

Elumi ist keine reine Vokabel-App, sondern eine Lernplattform, die reale Inhalte in bearbeitbaren Lernstoff verwandelt. Der stärkste Kern ist der Scan-Review-Import-Loop. Der wichtigste Unterschied zum Wettbewerb kann werden:

- echte Foto-/Scan-Nutzung
- intelligenter Freitext-Workflow
- lokaler Wissenspool
- GPT-gestützte Strukturierung schwieriger Inhalte
- eine starke, eigenständige visuelle Welt

Genau deshalb sollte jedes Review nicht nur die Screens anschauen, sondern bewerten, ob aus diesen Bausteinen ein klares, vertrauenswürdiges und motivierendes Lernprodukt entsteht.
