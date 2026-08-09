/*
 * Haute42 — scale-mapper for a button controller on the USB-A port.
 *
 * The controller (see firmware/) is deliberately dumb: 16 buttons, 16 fixed
 * note numbers, always on MIDI channel 16. This module turns those into
 * musical notes — root, scale, octave — and injects them either into one of
 * Move's four native tracks or into a Schwung slot synth.
 *
 * Cascade safety: we inject on cable 2, which is the same buffer that feeds
 * onMidiMessageExternal, so an injected note can come straight back to us.
 * The guard is channel separation, not refcounting — the controller is the
 * only thing that ever sends on channel 16, and we never inject there. Any
 * echo arrives on the destination channel and is dropped by the first test
 * in onMidiMessageExternal. This is why docs/MIDI_INJECTION.md's warning
 * about re-injecting from onMidiMessageExternal does not bite here.
 */

import { announce, announceMenuItem } from
    '/data/UserData/schwung/shared/screen_reader.mjs';
import { decodeDelta, setLED } from
    '/data/UserData/schwung/shared/input_filter.mjs';
import { Black, DarkGrey, BrightGreen } from
    '/data/UserData/schwung/shared/constants.mjs';

/* ---- Contract with the firmware ---- */

const IN_CHANNEL  = 15;   /* controller transmits on MIDI channel 16 */
const BASE_NOTE   = 36;   /* firmware's button 0 */
const NUM_BUTTONS = 16;
const CC_OCT_DOWN = 20;
const CC_OCT_UP   = 21;
const CC_PANIC    = 22;

/* ---- Move surface CCs ---- */

const CC_KNOB1 = 71;
const CC_KNOB2 = 72;
const CC_KNOB3 = 73;
const CC_KNOB4 = 74;

/* ---- Musical tables ---- */

const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G",
                    "G#", "A", "A#", "B"];

const SCALES = [
    { name: "Major",     steps: [0, 2, 4, 5, 7, 9, 11] },
    { name: "Minor",     steps: [0, 2, 3, 5, 7, 8, 10] },
    { name: "Dorian",    steps: [0, 2, 3, 5, 7, 9, 10] },
    { name: "Mixolyd",   steps: [0, 2, 4, 5, 7, 9, 10] },
    { name: "Pent Maj",  steps: [0, 2, 4, 7, 9] },
    { name: "Pent Min",  steps: [0, 3, 5, 7, 10] },
    { name: "Blues",     steps: [0, 3, 5, 6, 7, 10] },
    { name: "Chromatic", steps: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] },
];

const ROOT_C3  = 48;      /* degree 0, root C, octave 0 lands here */
const VELOCITY = 100;
const OCT_MIN  = -3;
const OCT_MAX  = 3;

/* ---- State ---- */

let root        = 0;      /* 0-11 */
let scaleIdx    = 0;
let octaveShift = 0;
let destCh      = 0;      /* 0-15; 0-3 are Move tracks 1-4 */
let lastNote    = "--";
let needsRedraw = true;

/* Sounding notes, indexed by the *incoming* note number so a note-off still
 * releases the right pitch after the scale or destination has been changed
 * mid-hold. -1 means "not held". */
const heldPitch = new Array(128).fill(-1);
const heldCh    = new Array(128).fill(-1);

/* ---- LED state ---- */

let ledInitPending = true;
let ledInitIndex   = 0;
const stepLedCache = new Array(NUM_BUTTONS).fill(-1);

/* ---- Note mapping ---- */

function degreeToPitch(degree) {
    const steps = SCALES[scaleIdx].steps;
    const n = steps.length;
    /* Math.floor so negative degrees wrap downward correctly. */
    const oct = Math.floor(degree / n);
    const idx = degree - oct * n;
    let p = ROOT_C3 + root + steps[idx] + 12 * oct + 12 * octaveShift;
    if (p < 0) p = 0;
    if (p > 127) p = 127;
    return p;
}

function pitchName(p) {
    return NOTE_NAMES[p % 12] + String(Math.floor(p / 12) - 1);
}

/* ---- Note output ---- */

function noteOn(inNote) {
    const degree = inNote - BASE_NOTE;
    if (degree < 0 || degree >= NUM_BUTTONS) return;

    /* Defensive: a retrigger without an intervening note-off would orphan
     * the previous pitch and leave it sounding forever. */
    if (heldPitch[inNote] >= 0) noteOff(inNote);

    const pitch = degreeToPitch(degree);
    move_midi_inject_to_move([0x29, 0x90 | destCh, pitch, VELOCITY]);
    heldPitch[inNote] = pitch;
    heldCh[inNote]    = destCh;

    lastNote    = pitchName(pitch);
    needsRedraw = true;
}

function noteOff(inNote) {
    const pitch = heldPitch[inNote];
    if (pitch < 0) return;
    move_midi_inject_to_move([0x28, 0x80 | heldCh[inNote], pitch, 0x40]);
    heldPitch[inNote] = -1;
    heldCh[inNote]    = -1;
    needsRedraw       = true;
}

function allNotesOff() {
    for (let i = 0; i < 128; i++) {
        if (heldPitch[i] >= 0) noteOff(i);
    }
}

/* ---- Drawing ---- */

function draw() {
    clear_screen();

    print(0, 0, "Haute42", 2);

    print(0, 22, NOTE_NAMES[root] + " " + SCALES[scaleIdx].name, 1);

    const octStr = (octaveShift >= 0 ? "+" : "") + String(octaveShift);
    print(0, 34, "Oct " + octStr, 1);
    print(56, 34, destCh < 4 ? ("Trk " + (destCh + 1))
                             : ("Ch " + (destCh + 1)), 1);

    print(0, 46, "Last " + lastNote, 1);
    print(0, 56, "K1 root K2 scl K3 oct K4 dst", 1);

    needsRedraw = false;
}

/* ---- LEDs ---- */

function ledInitStep() {
    /* Clear the pad grid 8 LEDs per frame — the output buffer holds ~64
     * packets and >60 in one frame overflows. */
    for (let i = 0; i < 8 && ledInitIndex < 32; i++, ledInitIndex++) {
        setLED(68 + ledInitIndex, Black, true);
    }
    if (ledInitIndex >= 32) ledInitPending = false;
}

function syncStepLeds() {
    /* Step LEDs 16-31 mirror which controller buttons are held. */
    for (let i = 0; i < NUM_BUTTONS; i++) {
        const color = heldPitch[BASE_NOTE + i] >= 0 ? BrightGreen : DarkGrey;
        if (stepLedCache[i] !== color) {
            setLED(16 + i, color, true);
            stepLedCache[i] = color;
        }
    }
}

/* ---- Parameter edits ---- */

function bumpOctave(delta) {
    const next = Math.max(OCT_MIN, Math.min(OCT_MAX, octaveShift + delta));
    if (next === octaveShift) return;
    octaveShift = next;
    announce("Octave " + (octaveShift >= 0 ? "+" : "") + octaveShift);
    needsRedraw = true;
}

function setDest(next) {
    if (next === destCh) return;
    /* Releasing first means the note-offs land on the channel the note-ons
     * went to; otherwise the old destination hangs. */
    allNotesOff();
    destCh = next;
    announce(destCh < 4 ? ("Track " + (destCh + 1))
                        : ("Channel " + (destCh + 1)));
    needsRedraw = true;
}

/* ---- Lifecycle ---- */

globalThis.init = function() {
    /* A remap left behind by a previously-run overtake module would rewrite
     * our channel 16 out from under us. */
    if (typeof host_ext_midi_remap_clear === "function") {
        host_ext_midi_remap_clear();
    }

    for (let i = 0; i < 128; i++) { heldPitch[i] = -1; heldCh[i] = -1; }
    for (let i = 0; i < NUM_BUTTONS; i++) stepLedCache[i] = -1;

    ledInitPending = true;
    ledInitIndex   = 0;
    lastNote       = "--";
    needsRedraw    = true;

    announceMenuItem("Haute42", NOTE_NAMES[root] + " " + SCALES[scaleIdx].name);
    draw();
};

globalThis.onResume = function() {
    /* LEDs were cleared while we were backgrounded — force a full repaint. */
    ledInitPending = true;
    ledInitIndex   = 0;
    for (let i = 0; i < NUM_BUTTONS; i++) stepLedCache[i] = -1;
    needsRedraw = true;
};

globalThis.tick = function() {
    if (ledInitPending) {
        ledInitStep();
        return;
    }
    syncStepLeds();
    if (needsRedraw) draw();
};

globalThis.onMidiMessageExternal = function(data) {
    if (!data) return;
    const status = data[0] | 0;
    const d1     = data[1] | 0;
    const d2     = data[2] | 0;

    /* Cascade guard: only the controller's channel is ours. Our own injected
     * notes come back on destCh and are dropped right here. */
    if ((status & 0x0F) !== IN_CHANNEL) return;

    const type = status & 0xF0;

    if (type === 0x90 && d2 > 0)                     { noteOn(d1);  return; }
    /* Note-on with velocity 0 is a note-off on many controllers. */
    if (type === 0x80 || (type === 0x90 && d2 === 0)) { noteOff(d1); return; }

    if (type === 0xB0 && d2 > 0) {
        if (d1 === CC_OCT_DOWN) bumpOctave(-1);
        else if (d1 === CC_OCT_UP) bumpOctave(1);
        else if (d1 === CC_PANIC) { allNotesOff(); announce("All notes off"); }
    }
};

globalThis.onMidiMessageInternal = function(data) {
    if (!data) return;
    const status = data[0] | 0;
    const d1     = data[1] | 0;
    const d2     = data[2] | 0;

    if ((status & 0xF0) !== 0xB0) return;   /* knobs only */

    const delta = decodeDelta(d2);
    if (delta === 0) return;
    const step = delta > 0 ? 1 : -1;

    if (d1 === CC_KNOB1) {
        root = (root + step + 12) % 12;
        announce(NOTE_NAMES[root]);
        needsRedraw = true;
    } else if (d1 === CC_KNOB2) {
        scaleIdx = (scaleIdx + step + SCALES.length) % SCALES.length;
        announce(SCALES[scaleIdx].name);
        needsRedraw = true;
    } else if (d1 === CC_KNOB3) {
        bumpOctave(step);
    } else if (d1 === CC_KNOB4) {
        setDest(Math.max(0, Math.min(15, destCh + step)));
    }
};
