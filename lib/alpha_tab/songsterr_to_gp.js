async (meta, parts) => {
  // AlphaTab's model warnings (e.g. falling back to custom bends for Songsterr's bend shapes) are expected; unmapped Songsterr data
  // is reported through `warnings` instead
  alphaTab.Logger.logLevel = alphaTab.LogLevel.Error;
  const m = alphaTab.model;
  const settings = new alphaTab.Settings();
  const warnings = new Map();
  const warn = (key) => warnings.set(key, (warnings.get(key) || 0) + 1);
  const checkKeys = (prefix, obj, known) => {
    for (const key of Object.keys(obj)) {
      if (!known.includes(key)) warn(`${prefix}.${key}`);
    }
  };

  // Older (version 5) tracks use a few different keys: measure.index, beat.dotted, beat.tempo (redundant with automations),
  // beat.wideVibrato, beat.harmonic, and note.velocity/grace/tremolo
  const MEASURE_KEYS = ['voices', 'signature', 'marker', 'rest', 'repeatStart', 'repeat', 'alternateEnding', 'tripletFeel',
    'doubleBarline', 'keySignature', 'index'];
  const VOICE_KEYS = ['beats', 'rest'];
  const BEAT_KEYS = ['notes', 'type', 'duration', 'dots', 'dotted', 'tempo', 'wideVibrato', 'harmonic', 'rest', 'tuplet',
    'tupletStart', 'tupletStop', 'palmMute', 'vibrato', 'vibratoWithTremoloBar', 'tremoloBar', 'letRing', 'chord', 'text',
    'velocity', 'gradualVelocity', 'graceNote', 'slapping', 'popping', 'tapping', 'brushStroke', 'arpeggio', 'upStroke',
    'downStroke', 'pickStroke', 'tremolo', 'beamStart', 'beamStop'];
  const NOTE_KEYS = ['fret', 'string', 'rest', 'tie', 'hp', 'dead', 'ghost', 'staccato', 'accentuated', 'vibrato',
    'leftHandVibrato', 'wideVibrato', 'slide', 'bend', 'harmonic', 'harmonicFret', 'velocity', 'grace', 'tremolo', 'trill', 'spn',
    'pickScrape'];

  const DYNAMICS = { ppp: m.DynamicValue.PPP, pp: m.DynamicValue.PP, p: m.DynamicValue.P, mp: m.DynamicValue.MP,
    mf: m.DynamicValue.MF, f: m.DynamicValue.F, ff: m.DynamicValue.FF, fff: m.DynamicValue.FFF };
  const SLIDES_OUT = { shift: m.SlideOutType.Shift, legato: m.SlideOutType.Legato, downwards: m.SlideOutType.OutDown,
    upwards: m.SlideOutType.OutUp };
  const SLIDES_IN = { below: m.SlideInType.IntoFromBelow, above: m.SlideInType.IntoFromAbove };
  const PICK_SCRAPES = { down: m.SlideOutType.PickSlideDown, up: m.SlideOutType.PickSlideUp };
  const TRIPLET_FEELS = { '8th': m.TripletFeel.Triplet8th, '16th': m.TripletFeel.Triplet16th };
  const HARMONICS = { natural: m.HarmonicType.Natural, artificial: m.HarmonicType.Artificial, pinch: m.HarmonicType.Pinch,
    tap: m.HarmonicType.Tap, semi: m.HarmonicType.Semi, feedback: m.HarmonicType.Feedback };
  const VIBRATOS = { slight: m.VibratoType.Slight, wide: m.VibratoType.Wide };
  // A note's spelling (spn, scientific pitch notation) is [step (C = 0), accidental, octave].  The accidental is taken from the
  // difference between the note's pitch and its step's natural pitch, rather than from the spelling's own accidental.
  const STEP_PITCHES = [0, 2, 4, 5, 7, 9, 11];
  const SPELLED_ACCIDENTALS = { '-2': m.NoteAccidentalMode.ForceDoubleFlat, '-1': m.NoteAccidentalMode.ForceFlat,
    0: m.NoteAccidentalMode.Default, 1: m.NoteAccidentalMode.ForceSharp, 2: m.NoteAccidentalMode.ForceDoubleSharp };
  const ACCENTS = { 1: m.AccentuationType.Normal, 2: m.AccentuationType.Heavy, true: m.AccentuationType.Normal };
  const CRESCENDOS = { crescendo: m.CrescendoType.Crescendo, decrescendo: m.CrescendoType.Decrescendo };
  const GRACES = { onBeat: m.GraceType.OnBeat, beforeBeat: m.GraceType.BeforeBeat };
  const BRUSHES = { up: m.BrushType.BrushUp, down: m.BrushType.BrushDown };
  const ARPEGGIOS = { up: m.BrushType.ArpeggioUp, down: m.BrushType.ArpeggioDown };
  const PICK_STROKES = { up: m.PickStroke.Up, down: m.PickStroke.Down };
  // Tremolo picking speed (note value denominator) to number of marks
  const TREMOLO_MARKS = { 8: 1, 16: 2, 32: 3, 64: 4, 128: 5 };
  // Looks up a Songsterr value in a mapping, warning about values it doesn't know
  const lookup = (mapping, key, value) => {
    if (value in mapping) return mapping[value];
    warn(`${key}=${value}`);
    return undefined;
  };
  const DRUMS_INSTRUMENT_ID = 1024;
  const isGuitarProgram = (program) => program >= 24 && program <= 39; // General MIDI guitars and basses

  const score = new m.Score();
  score.title = meta.title || '';
  score.artist = meta.artist || '';
  const tempos = parts[0]?.automations?.tempo || [];
  score.tempo = tempos[0]?.bpm || 120;

  // Master bars: shared across tracks, attributes taken from the first part that defines them
  const barCount = Math.max(...parts.map((part) => part.measures.length));
  let signature = [4, 4];
  let tripletFeel = m.TripletFeel.NoTripletFeel;
  const doubleBarlines = new Set();
  // Key signature of each master bar, as [KeySignature, KeySignatureType]; applied to every track's bar, since Guitar Pro stores
  // keys per master bar
  const keySignatures = [];
  let keySignature = [m.KeySignature.C, m.KeySignatureType.Major];
  for (let i = 0; i < barCount; i++) {
    const masterBar = new m.MasterBar();
    const measures = parts.map((part) => part.measures[i]).filter(Boolean);
    const find = (key) => measures.find((measure) => measure[key] !== undefined)?.[key];

    signature = find('signature') || signature;
    [masterBar.timeSignatureNumerator, masterBar.timeSignatureDenominator] = signature;

    // Triplet feel applies until changed, like the time signature
    const feel = find('tripletFeel');
    if (feel !== undefined) {
      if (feel in TRIPLET_FEELS) tripletFeel = TRIPLET_FEELS[feel];
      else warn(`measure.tripletFeel=${feel}`);
    }
    masterBar.tripletFeel = tripletFeel;

    // accidentalCount is signed (negative for flats), like Guitar Pro's; transposeAs is just a spelling preference
    const key = find('keySignature');
    if (key) {
      keySignature = [key.accidentalCount ?? 0, key.mode === 'minor' ? m.KeySignatureType.Minor : m.KeySignatureType.Major];
    }
    keySignatures[i] = keySignature;

    const marker = find('marker');
    if (marker?.text) {
      masterBar.section = new m.Section();
      masterBar.section.text = marker.text;
    }
    if (find('repeatStart')) masterBar.isRepeatStart = true;
    const repeat = find('repeat');
    if (repeat) masterBar.repeatCount = (repeat === true) ? 2 : repeat;
    // isDoubleBar is deprecated in favor of Bar.barLineRight, but it's what the Guitar Pro 7 format stores
    if (find('doubleBarline')) {
      masterBar.isDoubleBar = true;
      doubleBarlines.add(i);
    }
    const endings = find('alternateEnding');
    if (endings) masterBar.alternateEndings = [].concat(endings).reduce((bits, n) => bits | (1 << (n - 1)), 0);

    score.addMasterBar(masterBar);
  }
  // Songsterr plays a repeat as many times as its alternate endings need, even past its repeat count (e.g. a repeat of 2 with
  // endings 1–5, then an ending 6 after it, plays 6 times), but AlphaTab stops at the count
  score.masterBars.forEach((closing, i) => {
    if (!closing.repeatCount) return;
    let start = i;
    while (start > 0 && !score.masterBars[start].isRepeatStart) start--;
    let end = i + 1;
    while (end < score.masterBars.length && score.masterBars[end].alternateEndings && !score.masterBars[end].isRepeatStart) end++;
    const endings = score.masterBars.slice(start, end).reduce((bits, bar) => bits | bar.alternateEndings, 0);
    closing.repeatCount = Math.max(closing.repeatCount, 32 - Math.clz32(endings));
  });
  // Automation measure numbers match measure.index, which is 1-based in older (version 5) tracks and absent (0-based) in newer ones
  const firstMeasureIndex = parts[0]?.measures[0]?.index ?? 0;
  for (const tempo of (tempos.length ? tempos : [{ measure: firstMeasureIndex, bpm: score.tempo }])) {
    const masterBar = score.masterBars[tempo.measure - firstMeasureIndex];
    if (masterBar) {
      masterBar.tempoAutomations.push(m.Automation.buildTempoAutomation(false, 0, tempo.bpm, 2));
    }
  }

  // MIDI channels are allocated in pairs (primary, secondary), skipping channel 9 which is reserved for percussion
  let nextChannel = 0;
  const allocateChannel = () => {
    if (nextChannel === 9) nextChannel++;
    return nextChannel++ % 16;
  };

  parts.forEach((part, partIndex) => {
    const info = meta.tracks[partIndex] || {};
    const track = new m.Track();
    track.ensureStaveCount(1);
    score.addTrack(track);
    track.name = info.title || part.instrument || '';
    track.shortName = track.name.substring(0, 10);

    const staff = track.staves[0];
    const isDrums = part.instrumentId === DRUMS_INSTRUMENT_ID;
    if (isDrums) {
      staff.isPercussion = true;
      track.playbackInfo.primaryChannel = track.playbackInfo.secondaryChannel = 9;
      staff.showTablature = false;
    } else {
      staff.stringTuning.tunings = part.tuning || info.tuning || [];
      track.playbackInfo.program = part.instrumentId;
      track.playbackInfo.primaryChannel = allocateChannel();
      track.playbackInfo.secondaryChannel = allocateChannel();
      // Guitars and basses are notated an octave above sounding pitch
      if (isGuitarProgram(part.instrumentId)) staff.displayTranspositionPitch = -12;
    }
    const clef = isDrums ? m.Clef.Neutral : info.isBassGuitar ? m.Clef.F4 : m.Clef.G2;
    const stringCount = part.strings || staff.stringTuning.tunings.length;

    let dynamics = m.DynamicValue.F;
    // AlphaTab (like Guitar Pro) needs every bar in a staff to have the same number of voices, so pad bars with empty voices
    const voiceCount = Math.max(1, ...part.measures.map((measure) => measure.voices.length));
    for (let i = 0; i < barCount; i++) {
      const measure = part.measures[i] || { voices: [] };
      checkKeys('measure', measure, MEASURE_KEYS);
      const bar = new m.Bar();
      bar.clef = clef;
      if (doubleBarlines.has(i)) bar.barLineRight = m.BarLineStyle.LightLight;
      [bar.keySignature, bar.keySignatureType] = keySignatures[i];
      staff.addBar(bar);

      const voices = [...measure.voices];
      while (voices.length < voiceCount) voices.push({ beats: [] });
      for (const songsterrVoice of voices) {
        checkKeys('voice', songsterrVoice, VOICE_KEYS);
        const voice = new m.Voice();
        bar.addVoice(voice);

        if (songsterrVoice.beats.length === 0) {
          const beat = new m.Beat();
          beat.isEmpty = true;
          voice.addBeat(beat);
        }
        for (const songsterrBeat of songsterrVoice.beats) {
          checkKeys('beat', songsterrBeat, BEAT_KEYS);
          const beat = new m.Beat();
          voice.addBeat(beat);
          beat.duration = songsterrBeat.type || m.Duration.Quarter;
          beat.dots = songsterrBeat.dots || (songsterrBeat.dotted ? 1 : 0);
          if (songsterrBeat.tuplet) {
            beat.tupletNumerator = songsterrBeat.tuplet;
            beat.tupletDenominator = 2 ** Math.floor(Math.log2(songsterrBeat.tuplet));
            if (beat.tupletDenominator === beat.tupletNumerator) beat.tupletDenominator /= 2;
          }
          const velocity = songsterrBeat.velocity ?? songsterrBeat.notes?.find((songsterrNote) => songsterrNote.velocity)?.velocity;
          if (velocity) dynamics = DYNAMICS[velocity] ?? dynamics;
          beat.dynamics = dynamics;
          if (songsterrBeat.vibratoWithTremoloBar) {
            if (songsterrBeat.vibratoWithTremoloBar in VIBRATOS) beat.vibrato = VIBRATOS[songsterrBeat.vibratoWithTremoloBar];
            else warn(`beat.vibratoWithTremoloBar=${songsterrBeat.vibratoWithTremoloBar}`);
          }
          if (songsterrBeat.graceNote) beat.graceType = lookup(GRACES, 'beat.graceNote', songsterrBeat.graceNote) ?? beat.graceType;
          if (songsterrBeat.gradualVelocity) {
            beat.crescendo = lookup(CRESCENDOS, 'beat.gradualVelocity', songsterrBeat.gradualVelocity) ?? beat.crescendo;
          }
          if (songsterrBeat.text?.text) beat.text = songsterrBeat.text.text;
          if (songsterrBeat.slapping) beat.slap = true;
          if (songsterrBeat.popping) beat.pop = true;
          if (songsterrBeat.tapping) beat.tap = true;
          if (songsterrBeat.upStroke) beat.pickStroke = m.PickStroke.Up;
          if (songsterrBeat.downStroke) beat.pickStroke = m.PickStroke.Down;
          if (songsterrBeat.pickStroke) {
            beat.pickStroke = lookup(PICK_STROKES, 'beat.pickStroke', songsterrBeat.pickStroke) ?? beat.pickStroke;
          }
          for (const [key, types] of [['brushStroke', BRUSHES], ['arpeggio', ARPEGGIOS]]) {
            if (!songsterrBeat[key]) continue;
            const brushType = lookup(types, `beat.${key}.direction`, songsterrBeat[key].direction);
            if (brushType !== undefined) {
              beat.brushType = brushType;
              beat.brushDuration = songsterrBeat[key].duration ?? 0; // MIDI ticks, like Guitar Pro
            }
          }
          if (songsterrBeat.tremolo) {
            const marks = lookup(TREMOLO_MARKS, 'beat.tremolo', songsterrBeat.tremolo[1]);
            if (marks !== undefined) {
              beat.tremoloPicking = new m.TremoloPickingEffect();
              beat.tremoloPicking.marks = marks;
            }
          }
          if (songsterrBeat.tremoloBar?.points?.length) {
            beat.whammyBarType = m.WhammyType.Custom;
            for (const point of songsterrBeat.tremoloBar.points) {
              beat.addWhammyBarPoint(new m.BendPoint(point.position, Math.round(point.tone / 25)));
            }
          }
          const chordName = songsterrBeat.chord?.text;
          if (chordName) {
            if (!staff.hasChord(chordName)) {
              const chord = new m.Chord();
              chord.name = chordName;
              chord.showDiagram = false;
              chord.showFingering = false;
              staff.addChord(chordName, chord);
            }
            beat.chordId = chordName;
          }
          if (songsterrBeat.rest) continue;

          for (const songsterrNote of songsterrBeat.notes || []) {
            checkKeys('note', songsterrNote, NOTE_KEYS);
            if (songsterrNote.rest) continue;
            const note = new m.Note();
            if (isDrums) {
              note.percussionArticulation = songsterrNote.fret;
            } else {
              note.fret = songsterrNote.fret ?? 0; // dead notes may have no fret
              note.string = stringCount - songsterrNote.string;
            }
            note.isTieDestination = !!songsterrNote.tie;
            note.isHammerPullOrigin = !!songsterrNote.hp;
            note.isDead = !!songsterrNote.dead;
            note.isGhost = !!songsterrNote.ghost;
            note.isLetRing = !!songsterrBeat.letRing;
            note.isStaccato = !!songsterrNote.staccato;
            note.isPalmMute = !!songsterrBeat.palmMute;
            if (songsterrNote.vibrato || songsterrBeat.vibrato) note.vibrato = m.VibratoType.Slight;
            if (songsterrBeat.wideVibrato || songsterrNote.wideVibrato) note.vibrato = m.VibratoType.Wide;
            if (songsterrNote.leftHandVibrato) {
              note.vibrato = lookup(VIBRATOS, 'note.leftHandVibrato', songsterrNote.leftHandVibrato) ?? note.vibrato;
            }
            if (songsterrNote.accentuated) {
              note.accentuated = lookup(ACCENTS, 'note.accentuated', songsterrNote.accentuated) ?? note.accentuated;
            }
            const harmonic = songsterrNote.harmonic ?? (songsterrBeat.harmonic ? 'natural' : undefined);
            if (harmonic) {
              if (harmonic in HARMONICS) {
                note.harmonicType = HARMONICS[harmonic];
                note.harmonicValue = songsterrNote.harmonicFret ?? note.fret;
              } else {
                warn(`note.harmonic=${harmonic}`);
              }
            }
            // A slide in and then out is named by joining them, e.g. 'belowlegato'
            const slide = songsterrNote.slide;
            if (slide && slide !== 'unknown') {
              const slideIn = Object.keys(SLIDES_IN).find((name) => slide.startsWith(name)) ?? '';
              const slideOut = slide.slice(slideIn.length);
              if (slideOut === '' || slideOut in SLIDES_OUT) {
                if (slideIn) note.slideInType = SLIDES_IN[slideIn];
                if (slideOut) note.slideOutType = SLIDES_OUT[slideOut];
              } else {
                warn(`note.slide=${slide}`);
              }
            }
            // AlphaTab treats a pick scrape as a kind of slide out
            if (songsterrNote.pickScrape) {
              note.slideOutType = lookup(PICK_SCRAPES, 'note.pickScrape', songsterrNote.pickScrape) ?? note.slideOutType;
            }
            // Older tracks flag tremolo picking without its speed; use the common unmeasured (3 mark) tremolo
            if (songsterrNote.tremolo && !beat.tremoloPicking) {
              beat.tremoloPicking = new m.TremoloPickingEffect();
              beat.tremoloPicking.marks = 3;
            }
            // note.grace in older tracks marks a note that's already notated (and timed) as a regular note, so it's ignored
            if (songsterrNote.bend?.points?.length) {
              note.bendType = m.BendType.Custom;
              for (const point of songsterrNote.bend.points) {
                note.addBendPoint(new m.BendPoint(point.position, Math.round(point.tone / 25)));
              }
            }
            beat.addNote(note);

            // The trill target is a pitch, which needs the note's string tuning (available once the note is added). Guitar Pro 7
            // files don't store the trill speed; older tracks' trills have no auxiliary fret at all, so can't be converted.
            const auxiliaryFret = songsterrNote.trill?.auxiliaryFret;
            if (auxiliaryFret !== undefined) note.trillValue = auxiliaryFret + note.stringTuning;
            else if (songsterrNote.trill) warn('note.trill');

            if (songsterrNote.spn && !isDrums) {
              const [step, , octave] = songsterrNote.spn;
              const pitch = note.fret + note.stringTuning;
              const accidental = SPELLED_ACCIDENTALS[pitch - (STEP_PITCHES[step] + 12 * (octave + 1))];
              if (accidental !== undefined) note.accidentalMode = accidental;
              else warn(`note.spn=${JSON.stringify(songsterrNote.spn)} for pitch ${pitch}`);
            }
          }
        }
      }
    }
  });

  score.finish(settings);

  const gp = new alphaTab.exporter.Gp7Exporter().export(score, settings);

  // Bars in playback order (repeats and alternate endings expanded by AlphaTab), as [masterBarIndex, occurrence]
  const generator = new alphaTab.midi.MidiFileGenerator(score, settings,
    new alphaTab.midi.AlphaSynthMidiFileHandler(new alphaTab.midi.MidiFile()));
  generator.generate();
  const occurrences = new Map();
  const playedBars = generator.tickLookup.masterBars.map((lookup) => {
    const index = lookup.masterBar.index;
    const occurrence = occurrences.get(index) ?? 0;
    occurrences.set(index, occurrence + 1);
    return [index, occurrence];
  });

  return {
    gp: Buffer.from(gp).toString('base64'),
    playedBars,
    warnings: [...warnings].map(([key, count]) => `${key} (${count}×)`),
  };
}
