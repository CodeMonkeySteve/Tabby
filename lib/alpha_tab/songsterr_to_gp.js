async (meta, parts) => {
  const m = alphaTab.model;
  const settings = new alphaTab.Settings();
  const warnings = new Map();
  const warn = (key) => warnings.set(key, (warnings.get(key) || 0) + 1);
  const checkKeys = (prefix, obj, known) => {
    for (const key of Object.keys(obj)) {
      if (!known.includes(key)) warn(`${prefix}.${key}`);
    }
  };

  const MEASURE_KEYS = ['voices', 'signature', 'marker', 'rest', 'repeatStart', 'repeat', 'alternateEnding', 'tripletFeel'];
  const VOICE_KEYS = ['beats', 'rest'];
  const BEAT_KEYS = ['notes', 'type', 'duration', 'dots', 'rest', 'tuplet', 'tupletStart', 'tupletStop', 'palmMute', 'vibrato',
    'vibratoWithTremoloBar', 'letRing', 'chord', 'velocity', 'beamStart', 'beamStop'];
  const NOTE_KEYS = ['fret', 'string', 'rest', 'tie', 'hp', 'dead', 'ghost', 'staccato', 'vibrato', 'slide', 'bend', 'harmonic',
    'harmonicFret'];

  const DYNAMICS = { ppp: m.DynamicValue.PPP, pp: m.DynamicValue.PP, p: m.DynamicValue.P, mp: m.DynamicValue.MP,
    mf: m.DynamicValue.MF, f: m.DynamicValue.F, ff: m.DynamicValue.FF, fff: m.DynamicValue.FFF };
  const SLIDES_OUT = { shift: m.SlideOutType.Shift, legato: m.SlideOutType.Legato, downwards: m.SlideOutType.OutDown,
    upwards: m.SlideOutType.OutUp };
  const SLIDES_IN = { intoFromBelow: m.SlideInType.IntoFromBelow, intoFromAbove: m.SlideInType.IntoFromAbove };
  const TRIPLET_FEELS = { '8th': m.TripletFeel.Triplet8th, '16th': m.TripletFeel.Triplet16th };
  const HARMONICS = { natural: m.HarmonicType.Natural, artificial: m.HarmonicType.Artificial, pinch: m.HarmonicType.Pinch,
    tap: m.HarmonicType.Tap, semi: m.HarmonicType.Semi, feedback: m.HarmonicType.Feedback };
  const VIBRATOS = { slight: m.VibratoType.Slight, wide: m.VibratoType.Wide };
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

    const marker = find('marker');
    if (marker?.text) {
      masterBar.section = new m.Section();
      masterBar.section.text = marker.text;
    }
    if (find('repeatStart')) masterBar.isRepeatStart = true;
    const repeat = find('repeat');
    if (repeat) masterBar.repeatCount = (repeat === true) ? 2 : repeat;
    const endings = find('alternateEnding');
    if (endings) masterBar.alternateEndings = [].concat(endings).reduce((bits, n) => bits | (1 << (n - 1)), 0);

    score.addMasterBar(masterBar);
  }
  for (const tempo of (tempos.length ? tempos : [{ measure: 0, bpm: score.tempo }])) {
    const masterBar = score.masterBars[tempo.measure];
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
    for (let i = 0; i < barCount; i++) {
      const measure = part.measures[i] || { voices: [] };
      checkKeys('measure', measure, MEASURE_KEYS);
      const bar = new m.Bar();
      bar.clef = clef;
      staff.addBar(bar);

      const voices = measure.voices.length ? measure.voices : [{ beats: [] }];
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
          beat.dots = songsterrBeat.dots || 0;
          if (songsterrBeat.tuplet) {
            beat.tupletNumerator = songsterrBeat.tuplet;
            beat.tupletDenominator = 2 ** Math.floor(Math.log2(songsterrBeat.tuplet));
            if (beat.tupletDenominator === beat.tupletNumerator) beat.tupletDenominator /= 2;
          }
          if (songsterrBeat.velocity) dynamics = DYNAMICS[songsterrBeat.velocity] ?? dynamics;
          beat.dynamics = dynamics;
          if (songsterrBeat.vibratoWithTremoloBar) {
            if (songsterrBeat.vibratoWithTremoloBar in VIBRATOS) beat.vibrato = VIBRATOS[songsterrBeat.vibratoWithTremoloBar];
            else warn(`beat.vibratoWithTremoloBar=${songsterrBeat.vibratoWithTremoloBar}`);
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
              note.fret = songsterrNote.fret;
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
            if (songsterrNote.harmonic) {
              if (songsterrNote.harmonic in HARMONICS) {
                note.harmonicType = HARMONICS[songsterrNote.harmonic];
                note.harmonicValue = songsterrNote.harmonicFret ?? note.fret;
              } else {
                warn(`note.harmonic=${songsterrNote.harmonic}`);
              }
            }
            if (songsterrNote.slide) {
              if (songsterrNote.slide in SLIDES_OUT) note.slideOutType = SLIDES_OUT[songsterrNote.slide];
              else if (songsterrNote.slide in SLIDES_IN) note.slideInType = SLIDES_IN[songsterrNote.slide];
              else warn(`note.slide=${songsterrNote.slide}`);
            }
            if (songsterrNote.bend?.points?.length) {
              note.bendType = m.BendType.Custom;
              for (const point of songsterrNote.bend.points) {
                note.addBendPoint(new m.BendPoint(point.position, Math.round(point.tone / 25)));
              }
            }
            beat.addNote(note);
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
