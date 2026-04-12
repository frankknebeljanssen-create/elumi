# Elumi Sound Engine — Integration Guide

## Installation

```bash
npm install tone
```

## Setup

Kopiere die Sound-Funktionen aus `elumi-arcade-sounds.jsx` in eine eigene Datei `sounds/elumiSounds.js` und exportiere die API:

```js
// sounds/elumiSounds.js
import * as Tone from 'tone';

// ... (alle ensureFX + play*-Funktionen + PLAY_MAP hierher kopieren)

export async function initAudio() {
  await Tone.start();
}

export function play(soundName) {
  const fn = PLAY_MAP[soundName];
  if (fn) fn();
  else console.warn(`[Elumi Sound] Unknown: "${soundName}"`);
}

export function stopLoop(loopName) {
  if (loopName === 'saugloop') stopSaugloop();
  if (loopName === 'scanprocess') stopScanprocess();
}

export const soundNames = Object.keys(PLAY_MAP);
```

## Verwendung in React

```jsx
import { initAudio, play } from './sounds/elumiSounds';

function QuizScreen() {
  useEffect(() => { initAudio(); }, []);

  const handleAnswer = (isCorrect) => {
    play(isCorrect ? 'correct' : 'wrong');
  };

  return <button onClick={() => handleAnswer(true)}>Antworten</button>;
}
```

## Alle verfügbaren Sound-Namen

### Quiz & Lernen
| Sound-Name     | Beschreibung              | Reuse von     |
|---------------|---------------------------|---------------|
| `correct`      | Richtige Antwort          | —             |
| `wrong`        | Falsche Antwort           | —             |
| `quizcomplete` | Quiz fertig               | —             |
| `streak`       | 5+ richtig hintereinander | —             |
| `xpgain`       | XP eingesammelt           | `snackcatch`  |
| `levelup`      | Level-Up / Meilenstein    | —             |

### Scan & Import
| Sound-Name      | Beschreibung           | Reuse von  |
|-----------------|------------------------|------------|
| `scanstart`      | Kamera-Klick           | —          |
| `scanprocess`    | Analyse-Loop (Toggle)  | —          |
| `scandone`       | Ergebnis-Ping          | —          |
| `importconfirm`  | Import bestätigt       | `correct`  |

### Karteikarten
| Sound-Name      | Beschreibung           |
|-----------------|------------------------|
| `cardflip`       | Karte umdrehen         |
| `cardright`      | Gewusst — wegswipen    |
| `cardwrong`      | Nicht gewusst          |
| `stackcomplete`  | Stapel komplett        |

### Navigation & UI
| Sound-Name   | Beschreibung           |
|-------------|------------------------|
| `appstart`   | App-Start Jingle       |
| `toggle`     | Toggle/Switch          |
| `tabswitch`  | Tab wechseln           |
| `listaction`  | Liste erstellt/gelöscht|
| `error`      | Fehlermeldung          |
| `favstar`    | Favorit markiert       |

### Gamification
| Sound-Name    | Beschreibung         | Reuse von    |
|--------------|----------------------|--------------|
| `dailystreak` | Täglicher Streak     | `streak`     |
| `achievement` | Achievement          | `roundclear` |
| `badge`       | Neues Badge          | `highscore`  |

### Arcade-Spiel
| Sound-Name   | Beschreibung          |
|-------------|------------------------|
| `gamestart`  | Spiel starten          |
| `snackcatch` | Snack fangen           |
| `combo`      | Combo-Kette            |
| `snackmiss`  | Snack verpasst (Bonk)  |
| `roundclear` | Runde geschafft        |
| `highscore`  | Neuer Highscore        |
| `gameover`   | Game Over              |

### Saugglocke
| Sound-Name  | Beschreibung              |
|------------|---------------------------|
| `saugstart` | Saugglocke aktiviert       |
| `saugloop`  | Saugstrahl-Surren (Toggle) |
| `saugend`   | Saugstrahl-Ende            |

### Power-Ups
| Sound-Name       | Beschreibung         |
|------------------|----------------------|
| `powerupspawn`    | Power-Up spawnt      |
| `bonusbubble`     | Bonus-Blase          |
| `slowmostart`     | Zeitlupe-Trank       |
| `slowmoend`       | Zeitlupe endet       |
| `shieldactivate`  | Schild aktiviert     |
| `shieldabsorb`    | Schild absorbiert    |

## Loops

Zwei Sounds sind Toggle-Loops (Start/Stop bei erneutem Aufruf):

```js
play('saugloop');     // 1. Aufruf: startet Loop
play('saugloop');     // 2. Aufruf: stoppt Loop

play('scanprocess');  // 1. Aufruf: startet Loop
play('scandone');     // Stoppt scanprocess automatisch

// Oder manuell:
stopLoop('saugloop');
stopLoop('scanprocess');
```

## React Native

Tone.js läuft im Browser/WebView. Für native iOS/Android-Apps:

1. **WebView-Ansatz:** Sound Engine in einem versteckten WebView laufen lassen
2. **Native Ansatz:** Die Tone.js-Parameter als Referenz für einen Sound-Designer nutzen, der daraus `.wav`-Dateien rendert, die ihr mit `expo-av` oder `react-native-sound` abspielt
3. **Hybrid:** UI-Sounds nativ (schneller), Arcade-Sounds im WebView

## Lautstärke anpassen

Jeder Sound hat einen `volume`-Parameter in dB. Zum globalen Anpassen:

```js
// In ensureFX():
masterLimiter = new Tone.Limiter(-3).toDestination();
// → Ändere -3 auf -6 für leiser, 0 für lauter
```
