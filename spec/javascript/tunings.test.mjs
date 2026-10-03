import assert from 'node:assert/strict'
import { test } from 'node:test'
import TrackTab from 'lib/track_tab'
import { noteNames, tuningGroups } from 'lib/tunings'
import { loadScore } from './helpers.mjs'

// A stand-in track tab in a tuning, playable in any tuning
const anyTab = originalTuning => ({ originalTuning, isPlayable: () => true })

test('names the open strings, lowest first', () => {
  assert.equal(noteNames([43, 38, 33, 28]), 'E A D G')
  assert.equal(noteNames([43, 38, 33, 28, 23]), 'B E A D G')
})

test("lists the presets of the track's family that reach its notes", () => {
  const groups = tuningGroups(new TrackTab(loadScore().tracks[0]), 'bass')
  assert.deepEqual(groups.map(group => group.label), ['4 strings', '5 strings', '6 strings'])
  const names = groups.flatMap(group => group.tunings.map(tuning => tuning.name))
  assert.ok(names.every(name => name.startsWith('Bass ')))
  assert.ok(names.includes('Bass Dropped D Tuning'))
  assert.ok(!names.includes('Bass Standard Tuning'))  // the track's own
  assert.deepEqual(groups[1].tunings, [
    { name: 'Bass 5 Strings Tuning', tuning: [43, 38, 33, 28, 23], label: 'Bass 5 Strings Tuning (B E A D G)' },
  ])
})

test('leaves out presets that can\'t reach every note', () => {
  const tab = { originalTuning: [43, 38, 33, 28], isPlayable: tuning => tuning.length === 5 }
  assert.deepEqual(tuningGroups(tab, 'bass').map(group => group.label), ['5 strings'])
})

test('finds the family from the instrument type for an unknown tuning, else matches the string count', () => {
  const custom = [64, 59, 55, 50, 45, 41]
  assert.deepEqual(tuningGroups(anyTab(custom), 'guitar').map(group => group.label), ['6 strings', '7 strings'])
  const sixStrings = tuningGroups(anyTab(custom), 'keys')
  assert.deepEqual(sixStrings.map(group => group.label), ['6 strings'])
  assert.ok(sixStrings[0].tunings.some(tuning => tuning.name === 'Bass 6 Strings Tuning'))
})
