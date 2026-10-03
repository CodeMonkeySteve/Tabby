import { model } from '@coderline/alphatab'

// The highest fret considered playable
export const MAX_FRET = 24

// The open pitch of a string (1 is the lowest) in a tuning (MIDI notes, highest string first, as in AlphaTab)
export function openPitch(tuning, string) {
  return tuning[tuning.length - string]
}

export function sameTuning(a, b) {
  return a.length === b.length && a.every((pitch, i) => pitch === b[i])
}

// Whether a staff is played on strings (so not a drum or piano staff)
export function isStringedStaff(staff) {
  return staff.isStringed && !staff.isPercussion
}

// A stringed track's notes and how the score fingers them, for playing them on other strings or in another tuning.  Notes are
// indexed in a fixed order (staves, bars, voices, beats, then notes), which keys an alternate tab's strings (see AlternateTab),
// so it mustn't change.
export default class TrackTab {
  static isStringed(track) {
    return track.staves.some(isStringedStaff)
  }

  constructor(track) {
    this.track = track
    this.staves = track.staves.filter(isStringedStaff)
    this.staffTunings = this.staves.map(staff => staff.stringTuning)
    this.originalTuning = [...this.staves[0].tuning]
    this.notes = []     // AlphaTab notes, by index
    this.original = []  // the score's fingering of each note
    for (const staff of this.staves) {
      const tuning = [...staff.tuning]
      for (const bar of staff.bars) {
        for (const voice of bar.voices) {
          for (const beat of voice.beats) {
            for (const note of beat.notes) this.addNote(note, tuning)
          }
        }
      }
    }
    this.indexes = new Map(this.notes.map((note, i) => [note, i]))
    this.groupChains()
    this.groupBeats()
  }

  addNote(note, tuning) {
    const open = openPitch(tuning, note.string)
    this.notes.push(note)
    this.original.push({
      string: note.string,
      fret: note.fret,
      open,
      pitch: note.fret + open,  // the fretted pitch, before any capo or transposition
      tuning,
      trill: note.isTrill ? note.trillValue : -1,
      natural: note.harmonicType === model.HarmonicType.Natural,
      bend: note.hasBend,
      dead: note.isDead,
    })
  }

  // Groups notes played as one on a string (tied, slid into, hammered-on, or pulled-off) into chains, numbered in note order
  groupChains() {
    const parents = this.notes.map((_, i) => i)
    const root = i => (parents[i] === i ? i : (parents[i] = root(parents[i])))
    for (const [i, note] of this.notes.entries()) {
      for (const other of [note.tieDestination, note.slideTarget, note.hammerPullDestination]) {
        if (other && this.indexes.has(other)) parents[root(this.indexes.get(other))] = root(i)
      }
    }
    const numbers = new Map()
    this.chains = this.notes.map((_, i) => {
      if (!numbers.has(root(i))) numbers.set(root(i), numbers.size)
      return numbers.get(root(i))
    })
    this.chainNotes = Array.from({ length: numbers.size }, () => [])
    this.chains.forEach((chain, i) => this.chainNotes[chain].push(i))
  }

  // Groups notes starting together (in any voice) into beats in time order, each ending when its longest note does
  groupBeats() {
    const beats = new Map()
    for (const [i, { beat }] of this.notes.entries()) {
      const key = `${beat.absolutePlaybackStart}/${beat.graceType}`
      if (!beats.has(key)) beats.set(key, { start: beat.absolutePlaybackStart, end: 0, notes: [] })
      const slice = beats.get(key)
      slice.end = Math.max(slice.end, beat.absolutePlaybackStart + beat.playbackDuration)
      slice.notes.push(i)
    }
    this.beats = [...beats.values()].sort((a, b) => a.start - b.start)
    this.beatOf = []
    this.beats.forEach((slice, b) => slice.notes.forEach(i => { this.beatOf[i] = b }))
  }

  // The note's string, given strings by note index (where they differ from the score's)
  stringOf(i, strings = {}) {
    return strings[i] ?? this.original[i].string
  }

  // The fret that plays the note's pitch on a string of a tuning (natural harmonics and dead notes keep their fret)
  fretOn(i, tuning, string) {
    const o = this.original[i]
    return o.dead || o.natural ? o.fret : o.pitch - openPitch(tuning, string)
  }

  // Where the note can be played in a tuning: the strings (and frets) in reach, with any trill, keeping natural harmonics'
  // pitch, and fretting bent notes (since an open string can't be bent)
  positions(i, tuning) {
    const o = this.original[i]
    const positions = []
    for (let string = 1; string <= tuning.length; string++) {
      if (o.natural && openPitch(tuning, string) !== o.open) continue
      const fret = this.fretOn(i, tuning, string)
      const trill = o.trill >= 0 ? o.trill + fret - o.fret : fret
      if (fret >= (o.bend ? 1 : 0) && fret <= MAX_FRET && trill >= 0 && trill <= MAX_FRET) positions.push({ string, fret })
    }
    return positions
  }

  // The strings every note of a chain can be played on in a tuning
  chainStrings(chain, tuning) {
    return this.chainNotes[chain]
      .map(i => this.positions(i, tuning).map(position => position.string))
      .reduce((strings, others) => strings.filter(string => others.includes(string)))
  }

  // Whether every chain of notes fits on some string of a tuning
  isPlayable(tuning) {
    return this.chainNotes.every((_, chain) => this.chainStrings(chain, tuning).length > 0)
  }

  // The fingering problem for an optimizer (see lib/fingering)
  problem(tuning) {
    return {
      stringCount: tuning.length,
      notes: this.original.map((o, i) => ({
        positions: this.positions(i, tuning), chain: this.chains[i], beat: this.beatOf[i], free: o.dead,
      })),
      beats: this.beats,
    }
  }

  // An optimizer's strings (by note index) as an alternate tab's: only those differing from the score's
  stringsFor(fingering) {
    return Object.fromEntries(fingering.flatMap((string, i) => (string === this.original[i].string ? [] : [[i, string]])))
  }

  // Fingers the notes in a tuning (null for the score's), with strings by note index (others keep the score's)
  apply(tuning = null, strings = {}) {
    this.staves.forEach((staff, s) => {
      staff.stringTuning = tuning ? TrackTab.tuningFor(tuning) : this.staffTunings[s]
    })
    for (const [i, note] of this.notes.entries()) {
      const o = this.original[i]
      note.string = this.stringOf(i, strings)
      note.fret = this.fretOn(i, tuning ?? o.tuning, note.string)
      if (o.trill >= 0) note.trillValue = o.trill + note.fret - o.fret
    }
  }

  // An AlphaTab tuning, named if it's a preset
  static tuningFor(tuning) {
    const preset = model.Tuning.findTuning(tuning)
    return new model.Tuning(preset?.name ?? '', [...tuning], preset?.isStandard ?? false)
  }

  // The next string the note's chain can move to in a tuning, up (1, toward higher-pitched strings) or down (-1), given
  // strings by note index, skipping strings out of reach or played by other notes starting with the chain's; or null
  moveTarget(i, tuning, strings, direction) {
    const chain = this.chains[i]
    const playable = this.chainStrings(chain, tuning)
    const members = this.chainNotes[chain]
    const taken = new Set(members
      .flatMap(member => this.beats[this.beatOf[member]].notes)
      .filter(other => this.chains[other] !== chain)
      .map(other => this.stringOf(other, strings)))
    for (let string = this.stringOf(i, strings) + direction; string >= 1 && string <= tuning.length; string += direction) {
      if (playable.includes(string) && !taken.has(string)) return string
    }
    return null
  }

  // The string changes (by note index) moving the note's chain to a string (null where that's the score's string)
  moveChanges(i, string) {
    const members = this.chainNotes[this.chains[i]]
    return Object.fromEntries(members.map(member => [member, string === this.original[member].string ? null : string]))
  }
}
