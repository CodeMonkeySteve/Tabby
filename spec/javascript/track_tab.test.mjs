import assert from 'node:assert/strict'
import { test } from 'node:test'
import { model } from '@coderline/alphatab'
import TrackTab, { MAX_FRET, openPitch, sameTuning } from 'lib/track_tab'
import { loadScore } from './helpers.mjs'

const STANDARD = [43, 38, 33, 28]
const DROP_D = [43, 38, 33, 26]
const FIVE_STRING = [43, 38, 33, 28, 23]
const MANDOLIN = [76, 69, 62, 55]

const bassTrack = () => loadScore().tracks[0]
const pitches = tab => tab.notes.map(note => note.realValue)

test('indexes the notes of the stringed staves', () => {
  const tab = new TrackTab(bassTrack())
  assert.ok(TrackTab.isStringed(tab.track))
  assert.equal(tab.notes.length, 477)
  assert.deepEqual(tab.originalTuning, STANDARD)
  assert.deepEqual(tab.original[0], {
    string: 2, fret: 0, open: 33, pitch: 33, tuning: STANDARD, trill: -1, natural: false, bend: false, dead: false,
  })
  assert.equal(openPitch(STANDARD, 1), 28)
  assert.ok(sameTuning(STANDARD, [43, 38, 33, 28]) && !sameTuning(STANDARD, FIVE_STRING) && !sameTuning(STANDARD, DROP_D))
})

test('chains tied, slid, and hammered notes', () => {
  const tab = new TrackTab(bassTrack())
  let connections = 0
  for (const [i, note] of tab.notes.entries()) {
    for (const other of [note.tieDestination, note.slideTarget, note.hammerPullDestination]) {
      if (!other) continue
      connections++
      assert.equal(tab.chains[tab.indexes.get(other)], tab.chains[i])
    }
  }
  assert.ok(connections > 0)
  assert.deepEqual(tab.chainNotes.flat().sort((a, b) => a - b), tab.notes.map((_, i) => i))
  assert.ok(tab.chainNotes.every((notes, chain) => notes.every(i => tab.chains[i] === chain)))
})

test('groups notes starting together into beats, in time order', () => {
  const tab = new TrackTab(bassTrack())
  assert.ok(tab.beats.every((beat, b) => b === 0 || beat.start > tab.beats[b - 1].start))
  assert.ok(tab.beats.every(beat => beat.end > beat.start && beat.notes.length > 0))
  assert.ok(tab.notes.every((_, i) => tab.beats[tab.beatOf[i]].notes.includes(i)))
})

test('fingers notes in another tuning keeping their pitch, and restores the score', () => {
  const tab = new TrackTab(bassTrack())
  const before = pitches(tab)
  const frets = tab.notes.map(note => note.fret)

  tab.apply(FIVE_STRING, Object.fromEntries(tab.notes.map((note, i) => [i, note.string + 1])))
  assert.equal(tab.staves[0].stringTuning.name, 'Bass 5 Strings Tuning')
  assert.deepEqual(tab.staves[0].tuning, FIVE_STRING)
  assert.deepEqual(pitches(tab), before)
  assert.deepEqual(tab.notes.map(note => note.fret), frets)

  tab.apply(DROP_D)
  assert.deepEqual(pitches(tab), before)
  assert.ok(tab.notes.every((note, i) => note.fret === frets[i] + (note.string === 1 ? 2 : 0)))

  tab.apply()
  assert.equal(tab.staves[0].stringTuning, tab.staffTunings[0])
  assert.deepEqual(pitches(tab), before)
  assert.deepEqual(tab.notes.map(note => [note.string, note.fret]), tab.original.map(o => [o.string, o.fret]))
})

test('finds where notes can be played', () => {
  const tab = new TrackTab(bassTrack())
  assert.deepEqual(tab.positions(0, STANDARD), [{ string: 1, fret: 5 }, { string: 2, fret: 0 }])  // an open A
  assert.deepEqual(tab.positions(0, MANDOLIN), [])
  assert.ok(tab.isPlayable(STANDARD) && tab.isPlayable(DROP_D) && tab.isPlayable(FIVE_STRING))
  assert.ok(!tab.isPlayable(MANDOLIN))
  assert.ok(tab.notes.every((_, i) => tab.positions(i, FIVE_STRING).every(({ fret }) => fret >= 0 && fret <= MAX_FRET)))
})

test('keeps natural harmonics on strings of the same pitch, and dead notes on their fret', () => {
  const track = bassTrack()
  const [harmonic, dead] = track.staves[0].bars.flatMap(bar => bar.voices[0].beats).flatMap(beat => beat.notes)
  Object.assign(harmonic, { harmonicType: model.HarmonicType.Natural, harmonicValue: 12, fret: 12 })
  dead.isDead = true
  const tab = new TrackTab(track)
  const deadIndex = tab.indexes.get(dead)

  assert.deepEqual(tab.positions(0, STANDARD), [{ string: 2, fret: 12 }])
  assert.deepEqual(tab.positions(0, FIVE_STRING), [{ string: 3, fret: 12 }])
  assert.deepEqual(tab.positions(0, DROP_D), [{ string: 2, fret: 12 }])
  assert.deepEqual(tab.positions(deadIndex, FIVE_STRING).map(p => p.fret), Array(5).fill(dead.fret))
  assert.equal(tab.problem(FIVE_STRING).notes[deadIndex].free, true)
})

test('keeps bent notes off open strings', () => {
  const track = bassTrack()
  const [note] = track.staves[0].bars.flatMap(bar => bar.voices[0].beats).flatMap(beat => beat.notes)  // an open A
  note.bendType = model.BendType.Bend
  note.addBendPoint(new model.BendPoint(0, 0))
  note.addBendPoint(new model.BendPoint(60, 4))
  const tab = new TrackTab(track)

  assert.deepEqual(tab.positions(0, STANDARD), [{ string: 1, fret: 5 }])
  assert.deepEqual(tab.problem(FIVE_STRING).notes[0].positions, [{ string: 1, fret: 10 }, { string: 2, fret: 5 }])
  assert.equal(tab.moveTarget(0, STANDARD, { 0: 1 }, 1), null)
})

test('describes the fingering problem, and keeps an optimizer\'s changed strings', () => {
  const tab = new TrackTab(bassTrack())
  const problem = tab.problem(FIVE_STRING)
  assert.equal(problem.stringCount, 5)
  assert.equal(problem.notes.length, 477)
  assert.deepEqual(problem.notes[0], { positions: tab.positions(0, FIVE_STRING), chain: tab.chains[0], beat: 0, free: false })
  assert.equal(problem.beats, tab.beats)
  assert.deepEqual(tab.stringsFor(tab.original.map(o => o.string).with(0, 3)), { 0: 3 })
})

test('moves a note and its chain to the next free string in reach', () => {
  const tab = new TrackTab(bassTrack())
  assert.equal(tab.moveTarget(0, STANDARD, {}, -1), 1)
  assert.equal(tab.moveTarget(0, STANDARD, {}, 1), null)  // an open A is out of reach on the D string
  assert.equal(tab.moveTarget(0, FIVE_STRING, { 0: 3 }, -1), 2)

  const chain = tab.chainNotes.find(notes => notes.length > 1)
  const string = tab.original[chain[0]].string === 4 ? 3 : 4
  assert.deepEqual(tab.moveChanges(chain[0], string), Object.fromEntries(chain.map(i => [i, string])))
  assert.deepEqual(tab.moveChanges(chain[0], tab.original[chain[0]].string), Object.fromEntries(chain.map(i => [i, null])))
})
