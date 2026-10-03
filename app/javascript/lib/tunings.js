import { model } from '@coderline/alphatab'
import { sameTuning } from 'lib/track_tab'

// Preset families (the first word of AlphaTab's preset names) by track instrument type, for tunings matching no preset
const FAMILIES = { bass: 'Bass', guitar: 'Guitar' }

// The most strings an AlphaTab preset has
const MAX_STRINGS = 10

// A tuning's open-string note names, lowest first, e.g. "E A D G"
export function noteNames(tuning) {
  return [...tuning].reverse().map(pitch => model.Tuning.getTextForTuning(pitch, false)).join(' ')
}

// The preset tunings a track could be played in, grouped by string count: those of its instrument family (from its tuning's
// preset, else its instrument type, else any preset with as many strings) that reach all of its notes, other than its own
export function tuningGroups(tab, instrumentType) {
  const original = tab.originalTuning
  const family = model.Tuning.findTuning(original)?.name.split(' ')[0] ?? FAMILIES[instrumentType]
  const groups = []
  for (let count = 1; count <= MAX_STRINGS; count++) {
    const tunings = model.Tuning.getPresetsFor(count)
      .filter(preset => (family ? preset.name.startsWith(`${family} `) : count === original.length))
      .filter(preset => !sameTuning(preset.tunings, original) && tab.isPlayable(preset.tunings))
      .map(preset => ({ name: preset.name, tuning: [...preset.tunings], label: `${preset.name} (${noteNames(preset.tunings)})` }))
    if (tunings.length > 0) groups.push({ label: `${count} strings`, tunings })
  }
  return groups
}
