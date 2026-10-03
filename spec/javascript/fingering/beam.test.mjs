import assert from 'node:assert/strict'
import { test } from 'node:test'
import beam from 'lib/fingering/beam'
import { DEFAULT_OPTIMIZER, optimizers } from 'lib/fingering'
import TrackTab from 'lib/track_tab'
import { fingeringProblem, loadScore } from '../helpers.mjs'

const GUITAR = [64, 59, 55, 50, 45, 40]
const FIVE_STRING_BASS = [43, 38, 33, 28, 23]

const fretsOf = (problem, strings) => strings.map((string, i) => problem.notes[i].positions.find(p => p.string === string).fret)

test('registers the beam optimizer as the default', () => {
  assert.equal(optimizers[DEFAULT_OPTIMIZER], beam)
})

test('plays a scale in the open position', async () => {
  const problem = fingeringProblem(GUITAR, [[48], [50], [52], [53], [55], [57], [59], [60]])  // C major, from the A string
  const strings = await beam(problem)
  const frets = fretsOf(problem, strings)
  assert.equal(strings[0], 2)  // the A string
  assert.ok(frets.every(fret => fret <= 4), `frets ${frets}`)
})

test('keeps a low riff in one position on a 5-string bass', async () => {
  const problem = fingeringProblem(FIVE_STRING_BASS, [[23], [25], [26], [28], [30], [25]])
  const strings = await beam(problem)
  assert.deepEqual(strings, [1, 1, 1, 2, 2, 1])
  assert.deepEqual(fretsOf(problem, strings), [0, 2, 3, 0, 2, 2])
})

test('keeps chained notes on one string', async () => {
  const unchained = fingeringProblem(GUITAR, [[57], [64]])
  assert.deepEqual(await beam(unchained), [4, 6])  // the E on the open string
  const slide = fingeringProblem(GUITAR, [[[57, 'slide']], [[64, 'slide']]])
  const strings = await beam(slide)
  assert.equal(strings[0], strings[1])
})

test('plays chords on separate strings', async () => {
  const problem = fingeringProblem(GUITAR, [[40, 47, 52]])
  assert.deepEqual(await beam(problem), [1, 2, 3])
})

test('avoids cutting off a ringing note', async () => {
  const problem = fingeringProblem(GUITAR, [[45], [52]])
  problem.beats[0].end = 2 * 960  // the A rings through the E
  const strings = await beam(problem)
  assert.equal(strings[0], 2)
  assert.notEqual(strings[1], 2)
})

test('ignores free notes for the hand position', async () => {
  const problem = fingeringProblem(GUITAR, [[47], [64], [47]], { free: [1] })  // a dead note between two B's
  problem.notes[1].positions = problem.notes[1].positions.map(p => ({ ...p, fret: 12 }))
  const strings = await beam(problem)
  assert.deepEqual([strings[0], strings[2]], [2, 2])  // both B's on the A string, though the dead note is at fret 12
})

test('returns null when the notes can\'t all be played', async () => {
  assert.equal(await beam(fingeringProblem([43, 38, 33, 28], [[28, 29]])), null)  // both only on the E string
  assert.equal(await beam(fingeringProblem([43, 38, 33, 28], [[20]])), null)
})

test('is deterministic', async () => {
  const problem = fingeringProblem(GUITAR, [[40, 47, 52], [45, 52, 57], [43, 50, 55], [64], [67], [71], [72, 76]])
  assert.deepEqual(await beam(problem), await beam(problem))
})

test('fingers a whole track in another tuning, quickly', async () => {
  const tab = new TrackTab(loadScore().tracks[0])
  const problem = tab.problem(FIVE_STRING_BASS)
  const started = performance.now()
  const strings = await beam(problem)
  assert.ok(performance.now() - started < 2000)
  assert.ok(strings.every((string, i) => problem.notes[i].positions.some(p => p.string === string)))
  assert.ok(tab.chainNotes.every(notes => notes.every(i => strings[i] === strings[notes[0]])))
})

test('fingers a long, dense track quickly', async () => {
  const pitches = Array.from({ length: 2000 }, (_, b) => [45 + ((b * 7) % 15), 52 + ((b * 7) % 15) + (b % 5)])
  const started = performance.now()
  assert.notEqual(await beam(fingeringProblem(GUITAR, pitches)), null)
  assert.ok(performance.now() - started < 5000, `took ${performance.now() - started}ms`)
})

test('fingers a long track of ringing chords quickly', async () => {
  let seed = 1
  const random = () => (seed = (seed * 16807) % 2147483647) / 2147483647
  const beats = Array.from({ length: 5000 }, () => {
    const root = 40 + Math.floor(random() * 20)
    return [0, 7, 12, 16].slice(0, 1 + Math.floor(random() * 4)).map(interval => root + interval)
  })
  const problem = fingeringProblem([64, 59, 55, 50, 45, 38], beats)  // Drop D
  for (const beat of problem.beats) beat.end = beat.start + 3 * 960  // each chord rings through the next two
  const started = performance.now()
  assert.notEqual(await beam(problem), null)
  assert.ok(performance.now() - started < 2000, `took ${performance.now() - started}ms`)
})

test('lets other work run while fingering a long track', async () => {
  let ran = false
  setTimeout(() => { ran = true })
  const fingering = beam(fingeringProblem(GUITAR, Array.from({ length: 2000 }, (_, b) => [45 + (b % 15)])))
  await fingering
  assert.ok(ran)
})

