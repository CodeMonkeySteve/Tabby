import { get as getScale } from '@tonaljs/scale'

// Keys are a tonic pitch class (C = 0) and one of the diatonic modes
export const MODES = ['ionian', 'dorian', 'phrygian', 'lydian', 'mixolydian', 'aeolian', 'locrian']

// Each mode's tonic, in semitones above its parent major (Ionian) root, which are also the major scale's steps
export const MODE_OFFSETS = [0, 2, 4, 5, 7, 9, 11]

// The parent major roots' spellings, with the fewest accidentals
const MAJOR_ROOTS = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']
const FLAT_ROOTS = [1, 3, 5, 8, 10]
const SHARPS = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
const FLATS = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B']

const ROLES = { 0: 'root', 2: 'third', 4: 'fifth' }

const pitchClass = n => ((n % 12) + 12) % 12
const symbols = name => name[0] + name.slice(1).replaceAll('#', '♯').replaceAll('b', '♭')
const capitalize = word => word[0].toUpperCase() + word.slice(1)

export function setRoot(key) {
  return pitchClass(key.tonic - MODE_OFFSETS[MODES.indexOf(key.mode)])
}

// The key's scale from its tonic, as `[pitchClass, name]`s spelled as its parent major spells them
function scale(key) {
  const root = setRoot(key)
  const names = getScale(`${MAJOR_ROOTS[root]} major`).notes
  const mode = MODES.indexOf(key.mode)
  return names.map((_, i) => {
    const step = (mode + i) % 7
    return [pitchClass(root + MODE_OFFSETS[step]), symbols(names[step])]
  })
}

export function keyName(key) {
  return `${scale(key)[0][1]} ${capitalize(key.mode)}`
}

export function scaleNotes(key) {
  return scale(key).map(([pitch, name], i) => {
    const accidental = pitchClass(pitch - key.tonic - MODE_OFFSETS[i] + 6) - 6
    const degree = `${(accidental < 0 ? '♭' : '♯').repeat(Math.abs(accidental))}${i + 1}`
    return { pitchClass: pitch, name, degree, role: ROLES[i] ?? 'scale' }
  })
}

// A note's name, in flats if the key's parent major is spelled with flats, else in sharps
export function noteName(pitch, key = null) {
  const flats = key && FLAT_ROOTS.includes(setRoot(key))
  return symbols((flats ? FLATS : SHARPS)[pitchClass(pitch)])
}

export function allKeys() {
  return Array.from({ length: 12 }, (_, tonic) => MODES.map(mode => ({ tonic, mode }))).flat()
}
