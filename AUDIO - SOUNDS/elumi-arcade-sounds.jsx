import { useState, useRef, useCallback, useEffect } from "react";
import * as Tone from "tone";

const C = {
  blush: "#FFB3BA", pink: "#FF4D80", rose: "#FF8FA3",
  navy: "#1A1A2E", midnight: "#0F2D48", dark: "#0A1628",
  white: "#FFF0F3", gold: "#FFD700", green: "#4ADE80", cyan: "#22D3EE",
  purple: "#B47AFF", orange: "#FF9F43", red: "#FF6B6B",
};

// ── SOUND CATEGORIES ──
const CATEGORIES = {
  lernapp: {
    label: "Lern-App",
    color: C.blush,
    sounds: {
      cardflip: { label: "Karteikarte umdrehen", emoji: "🔄", desc: "Weicher Swoosh", color: C.cyan },
    },
  },
  spielablauf: {
    label: "Spielablauf",
    color: C.pink,
    sounds: {
      gamestart: { label: "Spiel starten", emoji: "🚀", desc: "Aufsteigende Töne", color: C.green },
      snackcatch: { label: "Snack fangen", emoji: "🍕", desc: "Kurzer Ding", color: C.gold },
      combo: { label: "Combo", emoji: "🔥", desc: "Schnelle Tonleiter", color: C.orange },
      snackmiss: { label: "Snack verpasst", emoji: "😤", desc: "Dumpfer Bonk", color: C.red },
      roundclear: { label: "Runde geschafft", emoji: "🏁", desc: "Mini-Fanfare", color: C.green },
      highscore: { label: "Neuer Highscore", emoji: "🏆", desc: "Jubel-Fanfare", color: C.gold },
      gameover: { label: "Game Over", emoji: "😵", desc: "Absteigende Töne", color: C.rose },
    },
  },
  sauger: {
    label: "Saugglocke",
    color: C.purple,
    sounds: {
      saugstart: { label: "Saugglocke aktiviert", emoji: "🌀", desc: "Saugstart-Whir", color: C.purple },
      saugloop: { label: "Saugstrahl-Surren", emoji: "〰️", desc: "Durchgehendes Summen", color: "#9B59B6" },
      saugend: { label: "Saugstrahl-Ende", emoji: "⬇️", desc: "Pitch-Drop runterfahren", color: "#8E44AD" },
    },
  },
  powerups: {
    label: "Power-Ups",
    color: C.green,
    sounds: {
      powerupspawn: { label: "Power-Up spawnt", emoji: "✨", desc: "Magischer Shimmer", color: C.cyan },
      bonusbubble: { label: "Bonus-Blase", emoji: "🫧", desc: "Fanfare aktiviert", color: C.gold },
      slowmostart: { label: "Zeitlupe-Trank", emoji: "🐌", desc: "Absteigender Ton", color: C.purple },
      slowmoend: { label: "Zeitlupe endet", emoji: "⚡", desc: "Speed-Up Ton", color: C.orange },
      shieldactivate: { label: "Schild aktiviert", emoji: "🛡️", desc: "Glas-Ping", color: C.cyan },
      shieldabsorb: { label: "Schild absorbiert", emoji: "💠", desc: "Dumpfes Knacken", color: "#5DADE2" },
    },
  },
};

// Flat map for easy access
const ALL_SOUNDS = {};
Object.values(CATEGORIES).forEach(cat =>
  Object.entries(cat.sounds).forEach(([k, v]) => { ALL_SOUNDS[k] = v; })
);

// ── SHARED FX ──
let masterReverb, masterLimiter;
function ensureFX() {
  if (!masterReverb) {
    masterLimiter = new Tone.Limiter(-3).toDestination();
    masterReverb = new Tone.Reverb({ decay: 1.8, wet: 0.35, preDelay: 0.01 }).connect(masterLimiter);
  }
  return { reverb: masterReverb, limiter: masterLimiter };
}

// Helper: dispose after ms
function disposeAfter(nodes, ms) {
  setTimeout(() => nodes.forEach(n => { try { n.dispose(); } catch(e){} }), ms);
}

// ══════════════════════════════════════════
// LERN-APP SOUNDS
// ══════════════════════════════════════════

function playCardflip() {
  const { reverb } = ensureFX();
  const synth = new Tone.FMSynth({
    harmonicity: 2.5, modulationIndex: 4,
    oscillator: { type: "sine" }, modulation: { type: "sine" },
    envelope: { attack: 0.02, decay: 0.22, sustain: 0, release: 0.3 },
    modulationEnvelope: { attack: 0.01, decay: 0.15, sustain: 0, release: 0.2 },
    volume: -12,
  }).connect(reverb);
  synth.triggerAttackRelease("G4", "8n");
  const air = new Tone.Synth({
    oscillator: { type: "sine" },
    envelope: { attack: 0.03, decay: 0.18, sustain: 0, release: 0.25 },
    volume: -18,
  }).connect(reverb);
  air.triggerAttackRelease("D6", "16n", "+0.04");
  disposeAfter([synth, air], 1200);
}

// ══════════════════════════════════════════
// SPIELABLAUF SOUNDS
// ══════════════════════════════════════════

function playGamestart() {
  const { reverb } = ensureFX();
  const chorus = new Tone.Chorus({ frequency: 2, delayTime: 3, depth: 0.5, wet: 0.4 }).connect(reverb);
  // Ascending warm FM notes — "Los geht's!" feeling
  const notes = ["C4", "E4", "G4", "C5", "E5"];
  notes.forEach((note, i) => {
    setTimeout(() => {
      const s = new Tone.FMSynth({
        harmonicity: 2.5, modulationIndex: 2,
        envelope: { attack: 0.02, decay: 0.2, sustain: 0.1, release: 0.35 },
        volume: -12 + i,
      }).connect(chorus);
      s.triggerAttackRelease(note, "8n");
      disposeAfter([s], 1000);
    }, i * 80);
  });
  // Final bright chord
  setTimeout(() => {
    ["G5", "C6", "E6"].forEach(note => {
      const pad = new Tone.FMSynth({
        harmonicity: 3, modulationIndex: 1,
        envelope: { attack: 0.03, decay: 0.5, sustain: 0.2, release: 0.7 },
        volume: -16,
      }).connect(chorus);
      pad.triggerAttackRelease(note, "4n");
      disposeAfter([pad], 1800);
    });
  }, 420);
  disposeAfter([chorus], 3000);
}

function playSnackcatch() {
  const { reverb } = ensureFX();
  // Quick satisfying "ding" — crystal bell, single tone
  const bell = new Tone.FMSynth({
    harmonicity: 5.1, modulationIndex: 8,
    oscillator: { type: "sine" }, modulation: { type: "triangle" },
    envelope: { attack: 0.001, decay: 0.3, sustain: 0, release: 0.35 },
    modulationEnvelope: { attack: 0.001, decay: 0.15, sustain: 0, release: 0.2 },
    volume: -12,
  }).connect(reverb);
  bell.triggerAttackRelease("A5", "16n");
  // Tiny shimmer tail
  const shim = new Tone.FMSynth({
    harmonicity: 7, modulationIndex: 3,
    envelope: { attack: 0.001, decay: 0.25, sustain: 0, release: 0.3 },
    volume: -18,
  }).connect(reverb);
  setTimeout(() => {
    shim.triggerAttackRelease("E6", "32n");
  }, 70);
  disposeAfter([bell, shim], 1000);
}

function playCombo() {
  const { reverb } = ensureFX();
  // Rapid ascending scale — excitement building
  const notes = ["E5", "G5", "A5", "B5", "D6", "E6"];
  notes.forEach((note, i) => {
    setTimeout(() => {
      const s = new Tone.FMSynth({
        harmonicity: 3, modulationIndex: 3,
        envelope: { attack: 0.005, decay: 0.12, sustain: 0, release: 0.15 },
        volume: -14 + i * 0.5,
      }).connect(reverb);
      s.triggerAttackRelease(note, "32n");
      disposeAfter([s], 600);
    }, i * 40);
  });
  // Sparkle at peak
  setTimeout(() => {
    const spark = new Tone.FMSynth({
      harmonicity: 8, modulationIndex: 10,
      envelope: { attack: 0.001, decay: 0.2, sustain: 0, release: 0.15 },
      volume: -18,
    }).connect(reverb);
    spark.triggerAttackRelease("G6", "32n");
    disposeAfter([spark], 600);
  }, 240);
}

function playSnackmiss() {
  const { reverb } = ensureFX();
  // Dull "bonk" — low FM thud, no harshness
  const bonk = new Tone.FMSynth({
    harmonicity: 1.2, modulationIndex: 8,
    oscillator: { type: "sine" }, modulation: { type: "sine" },
    envelope: { attack: 0.005, decay: 0.2, sustain: 0, release: 0.12 },
    modulationEnvelope: { attack: 0.005, decay: 0.1, sustain: 0, release: 0.08 },
    volume: -8,
  }).connect(reverb);
  bonk.triggerAttackRelease("G2", "16n");
  // Soft filtered thump layer
  const lpf = new Tone.Filter({ frequency: 300, type: "lowpass", rolloff: -24 }).connect(reverb);
  const thump = new Tone.NoiseSynth({
    noise: { type: "brown" },
    envelope: { attack: 0.005, decay: 0.12, sustain: 0, release: 0.08 },
    volume: -14,
  }).connect(lpf);
  thump.triggerAttackRelease("32n");
  disposeAfter([bonk, thump, lpf], 800);
}

function playRoundclear() {
  const { reverb } = ensureFX();
  const chorus = new Tone.Chorus({ frequency: 2.5, delayTime: 3, depth: 0.5, wet: 0.4 }).connect(reverb);
  // Mini fanfare — short & triumphant
  const melody = [
    { note: "G5", delay: 0 },
    { note: "B5", delay: 80 },
    { note: "D6", delay: 160 },
    { note: "G6", delay: 280 },
  ];
  melody.forEach(({ note, delay }) => {
    setTimeout(() => {
      const s = new Tone.FMSynth({
        harmonicity: 2.5, modulationIndex: 2,
        envelope: { attack: 0.01, decay: 0.2, sustain: 0.1, release: 0.4 },
        volume: -12,
      }).connect(chorus);
      s.triggerAttackRelease(note, "8n");
      disposeAfter([s], 1200);
    }, delay);
  });
  // Sustain chord
  setTimeout(() => {
    ["G5", "B5", "D6"].forEach(note => {
      const pad = new Tone.Synth({
        oscillator: { type: "sine" },
        envelope: { attack: 0.04, decay: 0.5, sustain: 0.15, release: 0.6 },
        volume: -18,
      }).connect(chorus);
      pad.triggerAttackRelease(note, "4n");
      disposeAfter([pad], 1500);
    });
  }, 350);
  disposeAfter([chorus], 3000);
}

function playHighscore() {
  const { reverb } = ensureFX();
  const chorus = new Tone.Chorus({ frequency: 2, delayTime: 4, depth: 0.6, wet: 0.5 }).connect(reverb);
  const delay = new Tone.FeedbackDelay({ delayTime: "16n", feedback: 0.2, wet: 0.15 }).connect(chorus);
  // Grand fanfare — longer & more celebratory than roundclear
  const notes = ["C5", "E5", "G5", "C6", "E6", "G6"];
  notes.forEach((note, i) => {
    setTimeout(() => {
      const s = new Tone.FMSynth({
        harmonicity: 3, modulationIndex: 2,
        envelope: { attack: 0.01, decay: 0.18, sustain: 0.12, release: 0.4 },
        volume: -13 + i * 0.3,
      }).connect(delay);
      s.triggerAttackRelease(note, "8n");
      disposeAfter([s], 1500);
    }, i * 65);
  });
  // Big bloom chord
  setTimeout(() => {
    ["C5", "E5", "G5", "B5", "C6"].forEach(note => {
      const pad = new Tone.FMSynth({
        harmonicity: 2, modulationIndex: 1,
        envelope: { attack: 0.04, decay: 0.8, sustain: 0.3, release: 1.2 },
        volume: -16,
      }).connect(chorus);
      pad.triggerAttackRelease(note, "2n");
      disposeAfter([pad], 3000);
    });
  }, 420);
  // Sparkle shower
  setTimeout(() => {
    [0, 80, 160, 240].forEach((d, i) => {
      setTimeout(() => {
        const sp = new Tone.FMSynth({
          harmonicity: 8, modulationIndex: 6,
          envelope: { attack: 0.001, decay: 0.15, sustain: 0, release: 0.1 },
          volume: -22,
        }).connect(reverb);
        sp.triggerAttackRelease(["E7", "G7", "C7", "D7"][i], "32n");
        disposeAfter([sp], 500);
      }, d);
    });
  }, 500);
  disposeAfter([chorus, delay], 4500);
}

function playGameover() {
  const { reverb } = ensureFX();
  const chorus = new Tone.Chorus({ frequency: 1.5, delayTime: 5, depth: 0.8, wet: 0.6 }).connect(reverb);
  // Gentle descending minor pads
  const chords = [["E4", "G4", "B4"], ["D4", "F4", "A4"], ["C4", "Eb4", "G4"]];
  chords.forEach((chord, ci) => {
    setTimeout(() => {
      chord.forEach(note => {
        const s = new Tone.Synth({
          oscillator: { type: "sine" },
          envelope: { attack: 0.08, decay: 0.5, sustain: 0.2, release: 0.8 },
          volume: -14,
        }).connect(chorus);
        s.triggerAttackRelease(note, "4n");
        disposeAfter([s], 2500);
      });
    }, ci * 400);
  });
  disposeAfter([chorus], 3500);
}

// ══════════════════════════════════════════
// SAUGGLOCKE SOUNDS
// ══════════════════════════════════════════

function playSaugstart() {
  const { reverb } = ensureFX();
  // Activation whir — ascending FM sweep with vortex modulation
  const whir = new Tone.FMSynth({
    harmonicity: 3, modulationIndex: 4,
    oscillator: { type: "sine" }, modulation: { type: "triangle" },
    envelope: { attack: 0.1, decay: 0.4, sustain: 0.3, release: 0.3 },
    modulationEnvelope: { attack: 0.05, decay: 0.3, sustain: 0.2, release: 0.2 },
    volume: -10,
  }).connect(reverb);
  whir.triggerAttackRelease("C3", "4n");
  whir.frequency.rampTo(800, 0.5);
  // Swirl layer
  const swirl = new Tone.FMSynth({
    harmonicity: 5, modulationIndex: 6,
    envelope: { attack: 0.08, decay: 0.35, sustain: 0.2, release: 0.25 },
    volume: -16,
  }).connect(reverb);
  swirl.triggerAttackRelease("G3", "8n");
  swirl.frequency.rampTo(600, 0.4);
  // Filtered whoosh
  const bpf = new Tone.Filter({ frequency: 400, type: "bandpass", Q: 1.5 }).connect(reverb);
  const whoosh = new Tone.NoiseSynth({
    noise: { type: "pink" },
    envelope: { attack: 0.1, decay: 0.4, sustain: 0.1, release: 0.2 },
    volume: -18,
  }).connect(bpf);
  whoosh.triggerAttackRelease("4n");
  bpf.frequency.rampTo(1500, 0.5);
  disposeAfter([whir, swirl, whoosh, bpf], 1500);
}

// Saugloop returns a stoppable object
let activeSaugloop = null;
function playSaugloop() {
  if (activeSaugloop) { stopSaugloop(); return; }
  const { reverb } = ensureFX();
  // Continuous humming drone — low FM with pulsing modulation
  const lfo = new Tone.LFO({ frequency: 3, min: 2, max: 6, type: "sine" }).start();
  const drone = new Tone.FMSynth({
    harmonicity: 2, modulationIndex: 3,
    oscillator: { type: "sine" }, modulation: { type: "sine" },
    envelope: { attack: 0.3, decay: 0.1, sustain: 0.8, release: 0.5 },
    modulationEnvelope: { attack: 0.2, decay: 0.1, sustain: 0.6, release: 0.4 },
    volume: -14,
  }).connect(reverb);
  lfo.connect(drone.modulationIndex);
  drone.triggerAttack("D3");
  // Higher shimmer layer
  const shimmer = new Tone.FMSynth({
    harmonicity: 6, modulationIndex: 4,
    envelope: { attack: 0.4, decay: 0.1, sustain: 0.6, release: 0.5 },
    volume: -22,
  }).connect(reverb);
  shimmer.triggerAttack("A4");
  // Subtle filtered noise texture
  const bpf = new Tone.Filter({ frequency: 600, type: "bandpass", Q: 3 }).connect(reverb);
  const noiseLoop = new Tone.NoiseSynth({
    noise: { type: "pink" },
    envelope: { attack: 0.5, decay: 0, sustain: 1, release: 0.5 },
    volume: -24,
  }).connect(bpf);
  noiseLoop.triggerAttack();
  activeSaugloop = { drone, shimmer, noiseLoop, lfo, bpf };
}

function stopSaugloop() {
  if (!activeSaugloop) return;
  const { drone, shimmer, noiseLoop, lfo, bpf } = activeSaugloop;
  drone.triggerRelease(); shimmer.triggerRelease(); noiseLoop.triggerRelease();
  setTimeout(() => {
    [drone, shimmer, noiseLoop, lfo, bpf].forEach(n => { try { n.dispose(); } catch(e){} });
  }, 800);
  activeSaugloop = null;
}

function playSaugend() {
  stopSaugloop();
  const { reverb } = ensureFX();
  // Pitch drop — high to low sweep, "powering down"
  const sweep = new Tone.FMSynth({
    harmonicity: 3, modulationIndex: 6,
    envelope: { attack: 0.03, decay: 0.8, sustain: 0.1, release: 0.4 },
    modulationEnvelope: { attack: 0.02, decay: 0.6, sustain: 0.05, release: 0.3 },
    volume: -10,
  }).connect(reverb);
  sweep.triggerAttackRelease("A4", "4n");
  sweep.frequency.rampTo(50, 0.7);
  // Air release
  const lpf = new Tone.Filter({ frequency: 1500, type: "lowpass" }).connect(reverb);
  const air = new Tone.NoiseSynth({
    noise: { type: "pink" },
    envelope: { attack: 0.02, decay: 0.5, sustain: 0, release: 0.3 },
    volume: -16,
  }).connect(lpf);
  air.triggerAttackRelease("4n");
  lpf.frequency.rampTo(100, 0.6);
  // Final thud
  setTimeout(() => {
    const thud = new Tone.FMSynth({
      harmonicity: 1.5, modulationIndex: 10,
      envelope: { attack: 0.005, decay: 0.18, sustain: 0, release: 0.1 },
      volume: -10,
    }).connect(reverb);
    thud.triggerAttackRelease("C2", "16n");
    disposeAfter([thud], 600);
  }, 550);
  disposeAfter([sweep, air, lpf], 1800);
}

// ══════════════════════════════════════════
// POWER-UP SOUNDS
// ══════════════════════════════════════════

function playPowerupspawn() {
  const { reverb } = ensureFX();
  const chorus = new Tone.Chorus({ frequency: 3, delayTime: 3, depth: 0.7, wet: 0.5 }).connect(reverb);
  // Magical shimmer — twinkling FM bells
  [0, 70, 140, 210, 280].forEach((d, i) => {
    setTimeout(() => {
      const s = new Tone.FMSynth({
        harmonicity: 6 + i, modulationIndex: 8 - i,
        envelope: { attack: 0.005, decay: 0.25, sustain: 0, release: 0.3 },
        volume: -18,
      }).connect(chorus);
      const notes = ["E6", "G6", "B6", "E7", "G7"];
      s.triggerAttackRelease(notes[i], "32n");
      disposeAfter([s], 800);
    }, d);
  });
  // Warm base tone
  const base = new Tone.FMSynth({
    harmonicity: 2, modulationIndex: 1,
    envelope: { attack: 0.05, decay: 0.4, sustain: 0.1, release: 0.5 },
    volume: -16,
  }).connect(chorus);
  base.triggerAttackRelease("C5", "8n");
  disposeAfter([base, chorus], 2000);
}

function playBonusbubble() {
  const { reverb } = ensureFX();
  const chorus = new Tone.Chorus({ frequency: 2, delayTime: 4, depth: 0.5, wet: 0.4 }).connect(reverb);
  // Bright fanfare — celebratory ascending
  const notes = ["E5", "G5", "B5", "E6"];
  notes.forEach((note, i) => {
    setTimeout(() => {
      const s = new Tone.FMSynth({
        harmonicity: 3, modulationIndex: 2,
        envelope: { attack: 0.01, decay: 0.2, sustain: 0.1, release: 0.35 },
        volume: -12,
      }).connect(chorus);
      s.triggerAttackRelease(note, "8n");
      disposeAfter([s], 1000);
    }, i * 70);
  });
  // Bloom
  setTimeout(() => {
    ["E5", "G#5", "B5"].forEach(note => {
      const pad = new Tone.Synth({
        oscillator: { type: "sine" },
        envelope: { attack: 0.04, decay: 0.5, sustain: 0.2, release: 0.7 },
        volume: -17,
      }).connect(chorus);
      pad.triggerAttackRelease(note, "4n");
      disposeAfter([pad], 1800);
    });
  }, 300);
  disposeAfter([chorus], 3000);
}

function playSlowmostart() {
  const { reverb } = ensureFX();
  // Descending tone — world slowing down
  const sweep = new Tone.FMSynth({
    harmonicity: 2, modulationIndex: 3,
    oscillator: { type: "sine" }, modulation: { type: "triangle" },
    envelope: { attack: 0.05, decay: 0.6, sustain: 0.15, release: 0.5 },
    volume: -10,
  }).connect(reverb);
  sweep.triggerAttackRelease("G5", "4n");
  sweep.frequency.rampTo(120, 0.5);
  // Warbly layer — pitch wobble for "time distortion"
  const warble = new Tone.FMSynth({
    harmonicity: 4, modulationIndex: 6,
    envelope: { attack: 0.03, decay: 0.5, sustain: 0.1, release: 0.4 },
    volume: -18,
  }).connect(reverb);
  warble.triggerAttackRelease("D5", "8n");
  warble.frequency.rampTo(80, 0.45);
  // Deep sub tone arriving
  setTimeout(() => {
    const sub = new Tone.Synth({
      oscillator: { type: "sine" },
      envelope: { attack: 0.1, decay: 0.4, sustain: 0.1, release: 0.3 },
      volume: -12,
    }).connect(reverb);
    sub.triggerAttackRelease("C2", "8n");
    disposeAfter([sub], 1000);
  }, 350);
  disposeAfter([sweep, warble], 1500);
}

function playSlowmoend() {
  const { reverb } = ensureFX();
  // Ascending speed-up — world coming back to speed
  const sweep = new Tone.FMSynth({
    harmonicity: 2.5, modulationIndex: 3,
    envelope: { attack: 0.03, decay: 0.5, sustain: 0.1, release: 0.3 },
    volume: -10,
  }).connect(reverb);
  sweep.triggerAttackRelease("C3", "4n");
  sweep.frequency.rampTo(1200, 0.45);
  // Accelerating clicks — like a tape speeding up
  [0, 80, 140, 185, 215, 235, 250].forEach((d, i) => {
    setTimeout(() => {
      const tick = new Tone.FMSynth({
        harmonicity: 6, modulationIndex: 8,
        envelope: { attack: 0.001, decay: 0.05, sustain: 0, release: 0.03 },
        volume: -20 + i,
      }).connect(reverb);
      tick.triggerAttackRelease(200 + i * 100, "64n");
      disposeAfter([tick], 300);
    }, d);
  });
  // Bright pop at end
  setTimeout(() => {
    const pop = new Tone.FMSynth({
      harmonicity: 5, modulationIndex: 4,
      envelope: { attack: 0.001, decay: 0.15, sustain: 0, release: 0.1 },
      volume: -14,
    }).connect(reverb);
    pop.triggerAttackRelease("G5", "16n");
    disposeAfter([pop], 600);
  }, 280);
  disposeAfter([sweep], 1200);
}

function playShieldactivate() {
  const { reverb } = ensureFX();
  // Glass ping — bright, crystalline, protective feel
  const glass = new Tone.FMSynth({
    harmonicity: 7, modulationIndex: 12,
    oscillator: { type: "sine" }, modulation: { type: "sine" },
    envelope: { attack: 0.001, decay: 0.5, sustain: 0, release: 0.6 },
    modulationEnvelope: { attack: 0.001, decay: 0.3, sustain: 0, release: 0.4 },
    volume: -12,
  }).connect(reverb);
  glass.triggerAttackRelease("E6", "8n");
  // Secondary harmonic
  setTimeout(() => {
    const h2 = new Tone.FMSynth({
      harmonicity: 9, modulationIndex: 8,
      envelope: { attack: 0.001, decay: 0.4, sustain: 0, release: 0.5 },
      volume: -16,
    }).connect(reverb);
    h2.triggerAttackRelease("B6", "16n");
    disposeAfter([h2], 1000);
  }, 60);
  // Sustaining shimmer
  const chorus = new Tone.Chorus({ frequency: 4, depth: 0.8, wet: 0.6 }).connect(reverb);
  const sustain = new Tone.Synth({
    oscillator: { type: "sine" },
    envelope: { attack: 0.05, decay: 0.6, sustain: 0.1, release: 0.5 },
    volume: -20,
  }).connect(chorus);
  sustain.triggerAttackRelease("E5", "4n");
  disposeAfter([glass, sustain, chorus], 2000);
}

function playShieldabsorb() {
  const { reverb } = ensureFX();
  // Dull crack/knack — impact absorbed by glass
  const crack = new Tone.FMSynth({
    harmonicity: 1.8, modulationIndex: 14,
    envelope: { attack: 0.002, decay: 0.12, sustain: 0, release: 0.08 },
    modulationEnvelope: { attack: 0.002, decay: 0.06, sustain: 0, release: 0.04 },
    volume: -8,
  }).connect(reverb);
  crack.triggerAttackRelease("A2", "32n");
  // Glass resonance after impact
  const ring = new Tone.FMSynth({
    harmonicity: 7, modulationIndex: 5,
    envelope: { attack: 0.01, decay: 0.35, sustain: 0, release: 0.3 },
    volume: -18,
  }).connect(reverb);
  setTimeout(() => {
    ring.triggerAttackRelease("C5", "16n");
  }, 40);
  // Filtered noise layer — the "crunch"
  const bpf = new Tone.Filter({ frequency: 800, type: "bandpass", Q: 2 }).connect(reverb);
  const crunch = new Tone.NoiseSynth({
    noise: { type: "white" },
    envelope: { attack: 0.002, decay: 0.08, sustain: 0, release: 0.05 },
    volume: -16,
  }).connect(bpf);
  crunch.triggerAttackRelease("64n");
  disposeAfter([crack, ring, crunch, bpf], 1000);
}

// ── PLAY MAP ──
const PLAY_MAP = {
  cardflip: playCardflip,
  gamestart: playGamestart,
  snackcatch: playSnackcatch,
  combo: playCombo,
  snackmiss: playSnackmiss,
  roundclear: playRoundclear,
  highscore: playHighscore,
  gameover: playGameover,
  saugstart: playSaugstart,
  saugloop: playSaugloop,
  saugend: playSaugend,
  powerupspawn: playPowerupspawn,
  bonusbubble: playBonusbubble,
  slowmostart: playSlowmostart,
  slowmoend: playSlowmoend,
  shieldactivate: playShieldactivate,
  shieldabsorb: playShieldabsorb,
};

// ══════════════════════════════════════════
// BGM
// ══════════════════════════════════════════
function createBGM() {
  const { reverb } = ensureFX();
  const vol = new Tone.Volume(-18).connect(reverb);
  const chorus = new Tone.Chorus({ frequency: 1.2, delayTime: 4, depth: 0.6, wet: 0.5 }).connect(vol);
  const dly = new Tone.FeedbackDelay({ delayTime: "8n.", feedback: 0.25, wet: 0.2 }).connect(chorus);

  const melodySynth = new Tone.FMSynth({
    harmonicity: 2, modulationIndex: 1.5,
    oscillator: { type: "sine" }, modulation: { type: "triangle" },
    envelope: { attack: 0.06, decay: 0.3, sustain: 0.2, release: 0.6 },
  }).connect(dly);

  const padSynth = new Tone.PolySynth(Tone.Synth, {
    oscillator: { type: "sine" },
    envelope: { attack: 0.3, decay: 0.8, sustain: 0.4, release: 1.2 },
    volume: -8,
  }).connect(chorus);

  const bassSynth = new Tone.Synth({
    oscillator: { type: "sine" },
    envelope: { attack: 0.05, decay: 0.3, sustain: 0.3, release: 0.5 },
    volume: -6,
  }).connect(vol);

  const melodyNotes = [
    { note: "E5", dur: "4n", time: "0:0:0" },
    { note: "G5", dur: "8n", time: "0:1:0" },
    { note: "A5", dur: "8n.", time: "0:1:2" },
    { note: "E5", dur: "4n", time: "0:2:2" },
    { note: "D5", dur: "8n", time: "0:3:2" },
    { note: "C5", dur: "4n", time: "1:0:0" },
    { note: "E5", dur: "8n", time: "1:1:0" },
    { note: "G5", dur: "4n.", time: "1:1:2" },
    { note: "A5", dur: "4n", time: "1:3:0" },
    { note: "B5", dur: "4n", time: "2:0:0" },
    { note: "A5", dur: "8n", time: "2:1:0" },
    { note: "G5", dur: "4n", time: "2:1:2" },
    { note: "E5", dur: "4n.", time: "2:3:0" },
    { note: "D5", dur: "4n", time: "3:0:0" },
    { note: "E5", dur: "8n", time: "3:1:0" },
    { note: "G5", dur: "4n", time: "3:1:2" },
    { note: "A5", dur: "2n", time: "3:2:2" },
  ];

  const padNotes = [
    { notes: ["C4", "E4", "G4"], time: "0:0:0", dur: "1m" },
    { notes: ["A3", "C4", "E4"], time: "1:0:0", dur: "1m" },
    { notes: ["F3", "A3", "C4"], time: "2:0:0", dur: "1m" },
    { notes: ["G3", "B3", "D4"], time: "3:0:0", dur: "1m" },
  ];

  const bassLine = [
    { note: "C2", dur: "2n", time: "0:0:0" }, { note: "G2", dur: "2n", time: "0:2:0" },
    { note: "A2", dur: "2n", time: "1:0:0" }, { note: "E2", dur: "2n", time: "1:2:0" },
    { note: "F2", dur: "2n", time: "2:0:0" }, { note: "C2", dur: "2n", time: "2:2:0" },
    { note: "G2", dur: "2n", time: "3:0:0" }, { note: "G2", dur: "2n", time: "3:2:0" },
  ];

  const mp = new Tone.Part((t, v) => melodySynth.triggerAttackRelease(v.note, v.dur, t), melodyNotes.map(n => [n.time, n]));
  mp.loop = true; mp.loopEnd = "4:0:0";
  const pp = new Tone.Part((t, v) => padSynth.triggerAttackRelease(v.notes, v.dur, t), padNotes.map(n => [n.time, n]));
  pp.loop = true; pp.loopEnd = "4:0:0";
  const bp = new Tone.Part((t, v) => bassSynth.triggerAttackRelease(v.note, v.dur, t), bassLine.map(n => [n.time, n]));
  bp.loop = true; bp.loopEnd = "4:0:0";

  return {
    start: () => { Tone.Transport.bpm.value = 90; mp.start(0); pp.start(0); bp.start(0); Tone.Transport.start(); },
    stop: () => { Tone.Transport.stop(); mp.stop(); pp.stop(); bp.stop(); },
    dispose: () => { [mp, pp, bp, melodySynth, padSynth, bassSynth, chorus, dly, vol].forEach(n => { try { n.dispose(); } catch(e){} }); },
  };
}

// ══════════════════════════════════════════
// UI COMPONENT
// ══════════════════════════════════════════
export default function ElumiArcadeSounds() {
  const [activeSound, setActiveSound] = useState(null);
  const [bgmPlaying, setBgmPlaying] = useState(false);
  const [saugloopActive, setSaugloopActive] = useState(false);
  const [toneReady, setToneReady] = useState(false);
  const [ripple, setRipple] = useState(null);
  const bgmRef = useRef(null);

  const initTone = useCallback(async () => {
    if (!toneReady) { await Tone.start(); setToneReady(true); }
  }, [toneReady]);

  const handlePlay = useCallback(async (key) => {
    await initTone();
    if (key === "saugloop") {
      if (activeSaugloop) { stopSaugloop(); setSaugloopActive(false); }
      else { playSaugloop(); setSaugloopActive(true); }
      return;
    }
    if (key === "saugend") {
      setSaugloopActive(false);
    }
    setActiveSound(key); setRipple(key);
    PLAY_MAP[key]();
    setTimeout(() => setActiveSound(null), 800);
    setTimeout(() => setRipple(null), 500);
  }, [initTone, saugloopActive]);

  const toggleBGM = useCallback(async () => {
    await initTone();
    if (bgmPlaying) {
      bgmRef.current?.stop(); bgmRef.current?.dispose(); bgmRef.current = null;
      setBgmPlaying(false);
    } else {
      bgmRef.current = createBGM(); bgmRef.current.start();
      setBgmPlaying(true);
    }
  }, [bgmPlaying, initTone]);

  useEffect(() => () => {
    bgmRef.current?.stop(); bgmRef.current?.dispose();
    stopSaugloop();
  }, []);

  return (
    <div style={{
      minHeight: "100vh",
      background: `radial-gradient(ellipse at 30% 20%, rgba(255,77,128,0.08) 0%, transparent 50%),
                    radial-gradient(ellipse at 70% 80%, rgba(34,211,238,0.06) 0%, transparent 50%),
                    linear-gradient(170deg, ${C.dark} 0%, ${C.midnight} 50%, ${C.navy} 100%)`,
      fontFamily: '"Nunito", system-ui, sans-serif',
      padding: "28px 16px 40px", color: C.white,
    }}>
      <link href="https://fonts.googleapis.com/css2?family=Nunito:wght@500;700;800;900&display=swap" rel="stylesheet" />
      <style>{`
        @keyframes rippleOut { 0% { transform: scale(0.85); opacity: 0.6; } 100% { transform: scale(1.15); opacity: 0; } }
        @keyframes pulseGlow { 0%,100% { box-shadow: 0 0 20px rgba(255,77,128,0.2); } 50% { box-shadow: 0 0 35px rgba(255,77,128,0.4); } }
        @keyframes float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-3px); } }
        @keyframes loopPulse { 0%,100% { opacity: 0.4; } 50% { opacity: 1; } }
        .sound-btn { transition: all 0.25s cubic-bezier(0.34,1.56,0.64,1); }
        .sound-btn:hover { transform: translateY(-2px); }
        .sound-btn:active { transform: scale(0.94); }
      `}</style>

      {/* Header */}
      <div style={{ textAlign: "center", marginBottom: 32 }}>
        <div style={{
          display: "inline-block", fontSize: 11, letterSpacing: 4, color: C.rose,
          textTransform: "uppercase", fontWeight: 800,
          background: "rgba(255,77,128,0.1)", padding: "4px 16px",
          borderRadius: 20, border: "1px solid rgba(255,77,128,0.15)", marginBottom: 10,
        }}>Elumi Arcade</div>
        <h1 style={{
          fontSize: 36, fontWeight: 900, margin: "8px 0 0",
          background: `linear-gradient(135deg, ${C.blush}, ${C.pink}, ${C.rose})`,
          WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent",
        }}>Sound Engine</h1>
        <p style={{ fontSize: 13, color: "rgba(255,179,186,0.4)", margin: "8px 0 0", fontWeight: 500 }}>
          17 Sounds · FM-Synthese · Reverb · Chorus · Alles programmatisch
        </p>
      </div>

      {/* Categories */}
      <div style={{ maxWidth: 680, margin: "0 auto" }}>
        {Object.entries(CATEGORIES).map(([catKey, cat]) => (
          <div key={catKey} style={{ marginBottom: 28 }}>
            {/* Category Header */}
            <div style={{
              display: "flex", alignItems: "center", gap: 8, marginBottom: 12,
              paddingLeft: 4,
            }}>
              <div style={{
                width: 4, height: 18, borderRadius: 2,
                background: cat.color,
              }} />
              <span style={{
                fontSize: 13, fontWeight: 800, color: cat.color,
                textTransform: "uppercase", letterSpacing: 2,
              }}>{cat.label}</span>
              <div style={{
                flex: 1, height: 1,
                background: `linear-gradient(90deg, ${cat.color}30, transparent)`,
              }} />
            </div>

            {/* Sound Grid */}
            <div style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fill, minmax(140px, 1fr))",
              gap: 8,
            }}>
              {Object.entries(cat.sounds).map(([key, snd]) => {
                const isActive = activeSound === key;
                const isRipple = ripple === key;
                const isLoop = key === "saugloop";
                const isLooping = isLoop && saugloopActive;
                return (
                  <div key={key} style={{ position: "relative" }}>
                    {isRipple && <div style={{
                      position: "absolute", inset: -4, borderRadius: 16,
                      border: `2px solid ${snd.color}`,
                      animation: "rippleOut 0.5s ease-out forwards",
                      pointerEvents: "none", zIndex: 2,
                    }} />}
                    <button className="sound-btn" onClick={() => handlePlay(key)} style={{
                      width: "100%",
                      background: isActive || isLooping
                        ? `linear-gradient(145deg, ${snd.color}20, ${snd.color}10)`
                        : "rgba(255,255,255,0.025)",
                      border: `1px solid ${isActive || isLooping ? snd.color + "60" : "rgba(255,179,186,0.08)"}`,
                      borderRadius: 14,
                      padding: "16px 8px 12px", cursor: "pointer",
                      backdropFilter: "blur(10px)", position: "relative", overflow: "hidden",
                    }}>
                      {(isActive || isLooping) && <div style={{
                        position: "absolute", inset: 0,
                        background: `radial-gradient(circle at center, ${snd.color}15, transparent 70%)`,
                      }} />}
                      <div style={{
                        fontSize: 26, marginBottom: 6,
                        animation: isActive ? "float 0.4s ease" : isLooping ? "loopPulse 1.5s ease-in-out infinite" : "none",
                        position: "relative",
                      }}>{snd.emoji}</div>
                      <div style={{ fontSize: 12, fontWeight: 800, color: C.white, position: "relative", lineHeight: 1.2 }}>
                        {snd.label}
                      </div>
                      <div style={{ fontSize: 9, color: "rgba(255,179,186,0.35)", marginTop: 3, position: "relative", fontWeight: 500 }}>
                        {isLooping ? "▶ läuft — tap to stop" : snd.desc}
                      </div>
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      {/* BGM Section */}
      <div style={{
        maxWidth: 680, margin: "0 auto",
        background: bgmPlaying ? "linear-gradient(135deg, rgba(255,77,128,0.08), rgba(34,211,238,0.05))" : "rgba(255,255,255,0.02)",
        border: `1px solid ${bgmPlaying ? "rgba(255,77,128,0.25)" : "rgba(255,179,186,0.06)"}`,
        borderRadius: 18, padding: "18px 24px",
        display: "flex", alignItems: "center", justifyContent: "space-between",
        backdropFilter: "blur(12px)",
        animation: bgmPlaying ? "pulseGlow 3s ease-in-out infinite" : "none",
      }}>
        <div>
          <div style={{ fontSize: 15, fontWeight: 800 }}>🎵 Hintergrundmusik</div>
          <div style={{ fontSize: 11, color: "rgba(255,179,186,0.4)", marginTop: 2, fontWeight: 500 }}>
            Lo-fi Ambient Loop · 90 BPM
          </div>
        </div>
        <button onClick={toggleBGM} className="sound-btn" style={{
          background: bgmPlaying ? `linear-gradient(135deg, ${C.pink}, #FF6B9D)` : "rgba(255,77,128,0.15)",
          border: "none", borderRadius: 12, padding: "10px 22px", cursor: "pointer",
          color: bgmPlaying ? "#fff" : C.rose, fontSize: 13, fontWeight: 800,
        }}>{bgmPlaying ? "⏹ Stop" : "▶ Play"}</button>
      </div>

      <p style={{ textAlign: "center", fontSize: 11, color: "rgba(255,179,186,0.2)", marginTop: 20, fontWeight: 500 }}>
        Alle Sounds via Tone.js · FM-Synthese · Keine Audiodateien nötig
      </p>
    </div>
  );
}
