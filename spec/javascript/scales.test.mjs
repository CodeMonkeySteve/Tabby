import assert from 'node:assert/strict'
import { test } from 'node:test'
import { MODES, allKeys, keyName, noteName, scaleNotes, setRoot } from 'lib/scales'

const key = (tonic, mode) => ({ tonic, mode })

test('names keys as modes, spelled from the parent major', () => {
  assert.equal(keyName(key(2, 'mixolydian')), "D Mixolydian")
  assert.equal(keyName(key(4, 'aeolian')), "E Aeolian")
  assert.equal(keyName(key(10, 'ionian')), "B♭ Ionian")
  assert.equal(keyName(key(6, 'ionian')), "F♯ Ionian")
  assert.equal(keyName(key(3, 'dorian')), "E♭ Dorian")
  assert.equal(setRoot(key(2, 'mixolydian')), 7)
})

test('lists the scale with degrees and roles', () => {
  assert.deepEqual(scaleNotes(key(2, 'mixolydian')).map(n => [n.pitchClass, n.name, n.degree, n.role]), [
    [2, 'D', '1', 'root'], [4, 'E', '2', 'scale'], [6, 'F♯', '3', 'third'], [7, 'G', '4', 'scale'],
    [9, 'A', '5', 'fifth'], [11, 'B', '6', 'scale'], [0, 'C', '♭7', 'scale'],
  ])
  assert.deepEqual(scaleNotes(key(9, 'aeolian')).map(n => n.degree), ['1', '2', '♭3', '4', '5', '♭6', '♭7'])
  assert.deepEqual(scaleNotes(key(5, 'lydian')).map(n => n.degree), ['1', '2', '3', '♯4', '5', '6', '7'])
  assert.deepEqual(scaleNotes(key(11, 'locrian')).map(n => n.degree), ['1', '♭2', '♭3', '4', '♭5', '♭6', '♭7'])
})

test('spells chromatic notes for the key', () => {
  assert.equal(noteName(5, key(2, 'mixolydian')), 'F')
  assert.equal(noteName(8, key(2, 'mixolydian')), 'G♯')
  assert.equal(noteName(6, key(5, 'ionian')), 'G♭')
  assert.equal(noteName(1), 'C♯')
})

test('lists every key', () => {
  assert.equal(allKeys().length, 84)
  assert.deepEqual(allKeys().slice(0, 2), [key(0, 'ionian'), key(0, 'dorian')])
  assert.deepEqual(MODES, ['ionian', 'dorian', 'phrygian', 'lydian', 'mixolydian', 'aeolian', 'locrian'])
})
