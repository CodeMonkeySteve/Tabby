import assert from 'node:assert/strict'
import { test } from 'node:test'
import { analyzeScore, barData, findKeys, regionIndexAt, trackPitchClasses } from 'lib/key_finder'
import { loadScore } from './helpers.mjs'

// A bar's data from quarter-note weights by pitch class (its home-note cues default to its weights)
function bar(notes, { cues = notes, signature = null, section = false } = {}) {
  const counts = values => Array.from({ length: 12 }, (_, pc) => values[pc] ?? 0)
  return { weights: counts(notes), cues: counts(cues), signature, section }
}

const sectioned = (song, starts) => song.map((b, i) => ({ ...b, section: starts.includes(i) }))

const bars = (count, notes, options) => Array.from({ length: count }, () => bar(notes, options))

test('finds the mode within the set from the home-note cues', () => {
  // G major's notes, centered on D
  const [region] = findKeys(bars(8, { 2: 3, 4: 1, 6: 1, 7: 1, 9: 2, 11: 1, 0: 1 }, { cues: { 2: 6, 9: 2, 7: 1 } }))
  assert.deepEqual([region.start, region.end, region.key], [0, 8, { tonic: 2, mode: 'mixolydian' }])
  assert.deepEqual(region.candidates.slice(0, 2).map(c => c.tonic), [2, 9])
  assert.equal(region.candidates.length, 7)
  assert.ok(Math.abs(region.candidates.reduce((sum, c) => sum + c.score, 0) - 1) < 1e-9)
})

test('starts a region where the note set changes, and not for a passing chromatic note', () => {
  const g = { 7: 3, 9: 1, 11: 2, 0: 1, 2: 2, 4: 1, 6: 1 }
  const a = { 9: 3, 11: 1, 1: 2, 2: 1, 4: 2, 6: 1, 8: 1 }
  const song = [...bars(8, g, { cues: { 7: 5 } }), ...bars(8, a, { cues: { 9: 5 } })]
  song[3] = bar({ ...g, 8: 1 }, { cues: { 7: 5 } })  // a passing G♯
  assert.deepEqual(findKeys(song).map(r => [r.start, r.end, r.key]), [
    [0, 8, { tonic: 7, mode: 'ionian' }], [8, 16, { tonic: 9, mode: 'ionian' }],
  ])
})

test('starts a region at the first bar of the new set when the windows see it coming early', () => {
  // F♯ major's chords, then a loud A–G vamp (D major's set) that pulls the windows over before its first bar
  const fSharp = [bar({ 1: 2, 3: 0.5, 6: 8, 8: 1.5 }), bar({ 1: 4, 3: 1, 8: 5, 10: 2 })]
  const vamp = [bar({ 1: 7.5, 2: 3, 4: 9.5, 9: 24, 11: 0.5 }), bar({ 0: 3.5, 2: 8, 7: 24.5, 9: 0.5, 11: 7.5 })]
  const song = [...Array(8).fill(fSharp).flat(), ...Array(8).fill(vamp).flat()]
  assert.deepEqual(findKeys(song).map(r => [r.start, r.end]), [[0, 16], [16, 32]])
})

test('moves a key change to a section start up to 2 bars away', () => {
  const g = { 7: 3, 9: 1, 11: 2, 0: 1, 2: 2, 4: 1, 6: 1 }
  const a = { 9: 3, 11: 1, 1: 2, 2: 1, 4: 2, 6: 1, 8: 1 }
  const song = [...bars(8, g, { cues: { 7: 5 } }), ...bars(8, a, { cues: { 9: 5 } })]
  const starts = notes => findKeys(sectioned([...song.slice(0, 6), bar(notes), bar(notes), ...song.slice(8)], [0, 6]))
    .map(r => r.start)
  // only across bars that don't clearly belong to the other set: here D, E, and A, in both
  assert.deepEqual([starts({ 2: 2, 4: 1, 9: 1 }), starts(g), starts(a)], [[0, 6], [0, 8], [0, 6]])
  assert.deepEqual(findKeys(sectioned(song, [0, 10])).map(r => r.start), [0, 8])
})

test('ignores a change of mode alone, unless a section starts there', () => {
  // A Mixolydian (D major's set), then a shorter passage of A Ionian (A major's set)
  const mixolydian = bars(12, { 9: 3, 11: 1, 1: 2, 2: 1, 4: 2, 6: 1, 7: 1 }, { cues: { 9: 6 } })
  const ionian = bars(6, { 9: 3, 11: 1, 1: 2, 2: 1, 4: 2, 6: 1, 8: 1 }, { cues: { 9: 6 } })
  const keys = sections => findKeys(sectioned([...mixolydian, ...ionian], sections)).map(r => [r.start, r.key.mode])
  assert.deepEqual(keys([0, 8, 16]), [[0, 'mixolydian']])
  assert.deepEqual(keys([0, 12]), [[0, 'mixolydian'], [12, 'ionian']])
  // A Phrygian (B♭ major's set) is too far from A Mixolydian for the two together to have a key
  const phrygian = bars(8, { 9: 3, 10: 2, 0: 2, 2: 1, 4: 2, 5: 2, 7: 1 }, { cues: { 9: 6 } })
  const far = findKeys(sectioned([...mixolydian, ...phrygian], [0])).map(r => [r.start, r.key?.mode])
  assert.deepEqual(far, [[0, 'mixolydian'], [12, 'phrygian']])
  // the passage joins what follows it, which then comes out in the key before it
  const back = findKeys(sectioned([...mixolydian, ...ionian, ...ionian, ...mixolydian, ...mixolydian], [0, 12]))
    .map(r => [r.start, r.key.mode])
  assert.deepEqual(back, [[0, 'mixolydian']])
})

test('moves a key change back to a section start across bars of the new set', () => {
  // the end of Easy (Commodores), whose last chorus moves up a half step at its section start (bar 16 here), while its
  // G♯s and Gs delay which new set the windows settle on
  const old = [{ 1: 4, 3: 5.8, 5: 6.5, 8: 2.3, 10: 6 }, { 0: 6.8, 3: 3.6, 5: 2.3, 7: 3.8, 8: 8.9, 10: 1.5 },
    { 0: 0.5, 1: 2, 3: 5.1, 5: 6.6, 8: 3.3, 10: 8 }, { 0: 6.8, 3: 6.8, 5: 0.5, 7: 1.8, 8: 7.4, 10: 3 }]
  const modulation = [
    { 1: 6.3, 2: 0.3, 4: 7.8, 6: 3.5, 8: 1.8, 9: 7.3, 11: 1 }, { 1: 0.5, 2: 2.2, 4: 5.2, 6: 5.5, 8: 1, 9: 4.2, 11: 7 },
    { 1: 6.3, 2: 0.3, 4: 6.8, 6: 0.5, 8: 1.8, 9: 8.3, 11: 1.5 }, { 1: 0.8, 2: 2.5, 4: 9, 6: 3.3, 9: 7.3, 11: 5.3 },
    { 1: 10.5, 2: 0.3, 4: 3.5, 6: 0.8, 8: 2, 9: 12, 11: 1.3 }, { 1: 0.5, 2: 2, 4: 3.3, 6: 5.3, 9: 2.3, 11: 7 },
    { 1: 0.3, 2: 4, 4: 2.3, 6: 5.5, 7: 4.5, 9: 4.8, 11: 2.8 }, { 1: 4, 4: 4, 9: 20 },
  ]
  const song = [...Array(4).fill(old).flat(), ...modulation].map(bar)
  assert.deepEqual(findKeys(sectioned(song, [0, 16])).map(r => r.start), [0, 16])
})

test('keeps regions at least 4 bars long when their boundaries move', () => {
  // a loud G major chord in F♯ minor turns the windows toward D major's set for longer than it lasts
  const fSharp = [bar({ 1: 3, 6: 4.5, 8: 1, 11: 1 }), bar({ 1: 2.5, 4: 1.3, 8: 1, 9: 2.8, 11: 1 })]
  const gChord = bar({ 2: 3, 6: 3, 7: 6 })
  const regions = n => findKeys([...Array(6).fill(fSharp).flat(), ...Array(n).fill(gChord), ...Array(6).fill(fSharp).flat()])
  assert.deepEqual([2, 3].map(n => regions(n).map(r => r.start)), [[0], [0]])
  const ending = findKeys([...Array(6).fill(fSharp).flat(), ...Array(3).fill(gChord)])
  assert.deepEqual(ending.map(r => [r.start, r.end]), [[0, 15]])
})

test('ignores a change of home note alone, unless a section starts there', () => {
  // B Aeolian with a touch of C, so G major's set is detected first, then D Ionian: both D major's set
  const aeolian = bars(8, { 11: 3, 2: 2, 4: 1, 6: 2, 7: 1, 9: 2, 0: 0.1 }, { cues: { 11: 6 } })
  const ionian = bars(8, { 2: 3, 4: 1, 6: 2, 7: 1, 9: 2, 11: 1, 1: 2 }, { cues: { 2: 6 } })
  const keys = sections => findKeys(sectioned([...aeolian, ...ionian], sections)).map(r => [r.start, r.key.tonic])
  assert.equal(keys([0]).length, 1)
  assert.deepEqual(keys([0, 8]), [[0, 11], [8, 2]])
})

test('sparse bars join a neighbor', () => {
  const song = [bar({}), bar({ 2: 0.25 }), ...bars(8, { 9: 2, 11: 1, 0: 2, 2: 1, 4: 2, 5: 1, 7: 1 }, { cues: { 9: 5 } }), bar({})]
  assert.deepEqual(findKeys(song).map(r => [r.start, r.end, r.key]), [[0, 11, { tonic: 9, mode: 'aeolian' }]])
})

test("a pentatonic riff keeps the previous region's set", () => {
  const song = [
    ...bars(8, { 2: 3, 4: 1, 6: 1, 7: 1, 9: 2, 11: 1, 0: 1 }, { cues: { 2: 5 } }),
    ...bars(4, { 2: 2, 4: 1, 9: 2, 11: 1 }, { cues: { 2: 5 } }),
  ]
  assert.equal(findKeys(song).length, 1)
})

test('nothing to call', () => {
  assert.deepEqual(findKeys([bar({}), bar({ 4: 0.25 })]), [{ start: 0, end: 2, key: null, candidates: [] }])
})

test("takes the home note and regions from the score's signatures, and detects the mode", () => {
  // "E minor" (1 sharp), but the notes are E Mixolydian's (A major's set)
  const song = [
    ...bars(6, { 4: 3, 6: 1, 8: 1, 9: 1, 11: 2, 1: 1, 2: 1 }, { cues: { 9: 9 }, signature: { id: '1/1', tonic: 4 } }),
    ...bars(4, { 9: 3, 11: 1, 1: 1, 2: 1, 4: 2, 6: 1, 8: 1 }, { signature: { id: '3/0', tonic: 9 } }),
  ]
  const regions = findKeys(song)
  assert.deepEqual(regions.map(r => [r.start, r.end, r.key]), [
    [0, 6, { tonic: 4, mode: 'mixolydian' }], [6, 10, { tonic: 9, mode: 'ionian' }],
  ])
  assert.ok(regions[0].candidates.every(c => c.tonic === 4))  // the ranked modes of the score's home note
})

test("mirrors a signature whose flats were read as sharps, and detects the set when neither fits", () => {
  // marked E major (4 sharps), but the notes are A♭ major's (4 flats)
  const ab = bars(6, { 8: 4, 3: 2, 5: 2, 0: 2, 1: 1, 10: 1, 7: 1 }, { cues: { 8: 6 }, signature: { id: '4/0', tonic: 4 } })
  assert.deepEqual(findKeys(ab)[0].key, { tonic: 8, mode: 'ionian' })
  // marked C major, but the notes are E major's, centered on E
  const e = bars(6, { 4: 4, 6: 1, 8: 2, 9: 1, 11: 2, 1: 1, 3: 1 }, { cues: { 4: 6 }, signature: { id: '0/0', tonic: 0 } })
  e.push(...bars(4, { 0: 4, 2: 1, 4: 2, 5: 1, 7: 2, 9: 1, 11: 1 }, { signature: { id: '-1/0', tonic: 5 } }))
  assert.deepEqual(findKeys(e)[0].key, { tonic: 4, mode: 'ionian' })
})

test('prefers the more common mode when the notes fit several sets', () => {
  // E, G, A, B, C, D: no F or F♯, so C major's and G major's sets fit equally
  const [region] = findKeys(bars(8, { 4: 3, 7: 1, 9: 1, 11: 1, 0: 1, 2: 1 }, { cues: { 4: 6 } }))
  assert.deepEqual(region.key, { tonic: 4, mode: 'aeolian' })
})

test('ranks a clear mode well ahead of the others', () => {
  const song = bars(6, { 4: 3, 6: 1, 8: 1, 9: 1, 11: 2, 1: 1, 2: 1 }, { signature: { id: '1/1', tonic: 4 } })
  assert.ok(findKeys(song)[0].candidates[0].score > 0.5)
})

test('merges neighboring regions that come out in the same key', () => {
  // B♭ minor with a chromatic F–F♯–G line, so the windows waver between B♭ Aeolian's and B♭ Dorian's sets
  const riff = { F: { 0: 1, 1: 1, 5: 1, 10: 1 }, G: { 0: 1, 1: 1, 7: 1, 10: 1 }, S: { 0: 1, 1: 1, 6: 1, 10: 1 } }
  const song = [...'SFSGFGGFFFFSGSGSSF'].map(k => bar(riff[k], { cues: { ...riff[k], 10: 4 } }))
  const regions = findKeys(song)
  assert.ok(regions.every((r, i) => i === 0 || r.key.mode !== regions[i - 1].key.mode || r.key.tonic !== regions[i - 1].key.tonic))
  assert.equal(regions.at(-1).end, 18)
})

test("keeps a signature's home note when its own set's other notes are just borrowed", () => {
  // marked G major (1 sharp), with G Dorian's notes (F major's set) centered on G
  const song = bars(6, { 7: 4, 5: 2, 10: 2, 4: 1, 0: 1, 2: 1, 9: 1 }, { cues: { 7: 8, 5: 2 }, signature: { id: '1/0', tonic: 7 } })
  assert.deepEqual(findKeys(song)[0].key, { tonic: 7, mode: 'dorian' })
})

test('merges score key changes that come out in the same key', () => {
  // marked B minor, then B major, with B Dorian's notes throughout
  const notes = { 11: 4, 1: 1, 2: 2, 4: 1, 6: 2, 8: 1, 9: 1 }
  const song = [
    ...bars(4, notes, { signature: { id: '2/1', tonic: 11 } }),
    ...bars(4, notes, { signature: { id: '5/0', tonic: 11 } }),
  ]
  assert.deepEqual(findKeys(song).map(r => [r.start, r.end, r.key]), [[0, 8, { tonic: 11, mode: 'dorian' }]])
})

test('calls each key of a song that modulates', () => {
  const g = { 7: 3, 9: 1, 11: 2, 0: 1, 2: 2, 4: 1, 6: 1 }
  const aFlat = { 8: 3, 10: 1, 0: 2, 1: 1, 3: 2, 5: 1, 7: 1 }
  const song = [...bars(40, g, { cues: { 7: 5 } }), ...bars(16, aFlat, { cues: { 8: 5 } })]
  assert.deepEqual(findKeys(song).map(r => [r.start, r.end, r.key]), [
    [0, 40, { tonic: 7, mode: 'ionian' }], [40, 56, { tonic: 8, mode: 'ionian' }],
  ])
})

test("joins a score's sparsely marked bars to a neighbor", () => {
  const e = { 4: 3, 6: 1, 8: 2, 9: 1, 11: 2, 1: 1, 3: 1 }
  const song = [
    bar({}, { signature: { id: '0/0', tonic: 0 } }),  // a count-in
    ...bars(6, e, { cues: { 4: 6 }, signature: { id: '4/0', tonic: 4 } }),
    bar({}, { signature: { id: '-2/0', tonic: 10 } }),
    ...bars(6, e, { cues: { 4: 6 }, signature: { id: '4/0', tonic: 4 } }),
  ]
  assert.deepEqual(findKeys(song).map(r => [r.start, r.end, r.key]), [[0, 14, { tonic: 4, mode: 'ionian' }]])
})

test('finds the region of a bar in either direction', () => {
  const regions = [{ start: 0, end: 4 }, { start: 4, end: 9 }, { start: 9, end: 12 }]
  assert.deepEqual([11, 4, 3, 0].map(b => regionIndexAt(regions, b)), [2, 1, 0, 0])
})

test("reads the fixture's notes and key signatures", () => {
  // Practice Etude: signatures G major (bars 0–7), A major (8–15), G major (16–23)
  const score = loadScore()
  const data = barData(score)
  assert.equal(data.length, score.masterBars.length)
  assert.deepEqual([data[0].signature, data[8].signature], [{ id: '1/0', tonic: 7 }, { id: '3/0', tonic: 9 }])
  assert.ok(data.some(b => b.weights.some(w => w > 0)))
  assert.ok(data.every(b => b.weights.length === 12 && b.cues.length === 12))
  const regions = analyzeScore(score)
  assert.deepEqual(regions.map(r => [r.start, r.end, r.key.tonic]), [[0, 8, 7], [8, 16, 9], [16, 24, 7]])
})

test('leaves signatures out when the score has none, and skips percussion', () => {
  const score = loadScore()
  for (const masterBar of score.masterBars) [masterBar.keySignature, masterBar.keySignatureType] = [0, 0]
  assert.ok(barData(score).every(b => b.signature === null))
  score.tracks[0].staves[0].isPercussion = true  // the fixture's only track
  assert.ok(barData(score).every(b => b.weights.every(w => w === 0)))
})

test('reads scores with very many notes', () => {
  const masterBar = { index: 0, keySignature: 0, keySignatureType: 0, timeSignatureNumerator: 4, calculateDuration: () => 3840 }
  const bar = { index: 0, masterBar, voices: [] }
  const voice = { bar, beats: [] }
  bar.voices.push(voice)
  for (let i = 0; i < 200000; i++) {
    voice.beats.push({ voice, isRest: false, playbackStart: 0, absolutePlaybackStart: i * 10, playbackDuration: 10,
                       notes: [{ realValue: 40, isDead: false, isTieDestination: false }] })
  }
  const score = { masterBars: [masterBar], tracks: [{ staves: [{ isPercussion: false, bars: [bar] }] }] }
  assert.ok(barData(score)[0].weights[4] > 0)
})

test('lists the pitch classes a track sounds in each bar', () => {
  const score = loadScore()
  const masks = trackPitchClasses(score.tracks[0])
  assert.equal(masks.length, score.masterBars.length)
  assert.ok(masks.some(mask => mask !== 0))
})
