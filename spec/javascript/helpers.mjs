import { readFileSync } from 'node:fs'
import { importer } from '@coderline/alphatab'

// Loads a score from spec/fixtures with AlphaTab
export function loadScore(name = 'Tears for Fears - Head Over Heels.gpx') {
  const bytes = readFileSync(new URL(`../fixtures/${name}`, import.meta.url))
  return importer.ScoreLoader.loadScoreFromBytes(new Uint8Array(bytes))
}

// Builds a fingering problem (see TrackTab#problem) from beats of pitches, each a MIDI note or a [note, chain] pair, played
// one after another in a tuning
export function fingeringProblem(tuning, beats, { maxFret = 24, free = [] } = {}) {
  const notes = []
  const slices = beats.map((pitches, b) => {
    const start = b * 960
    const indexes = pitches.map(entry => {
      const [pitch, chain] = Array.isArray(entry) ? entry : [entry, `note ${notes.length}`]
      const positions = []
      for (let string = 1; string <= tuning.length; string++) {
        const fret = pitch - tuning[tuning.length - string]
        if (fret >= 0 && fret <= maxFret) positions.push({ string, fret })
      }
      notes.push({ positions, pitch, chain, beat: b, free: free.includes(notes.length) })
      return notes.length - 1
    })
    return { start, end: start + 960, notes: indexes }
  })
  return { stringCount: tuning.length, notes, beats: slices }
}
