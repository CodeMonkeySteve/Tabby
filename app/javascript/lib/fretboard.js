import { noteName } from 'lib/scales'

const LEFT = 40
const TOP = 22
const FRET_WIDTH = 46
const STRING_SPACING = 38
const RADIUS = 15
const ROOT_RADIUS = 16
const NUMBERED_FRETS = [0, 3, 5, 7, 9]  // modulo 12

const NUT = LEFT + FRET_WIDTH

const fretX = fret => (fret === 0 ? LEFT + FRET_WIDTH / 2 - 2 : NUT + (fret - 0.5) * FRET_WIDTH)

function marker({ name, degree, role }, string, fret, y) {
  const x = fretX(fret)
  const radius = role === 'root' ? ROOT_RADIUS : RADIUS
  const label = degree
    ? `<text class="fb-name" x="${x}" y="${y + 3}">${name}</text><text class="fb-degree" x="${x}" y="${y + 13}">${degree}</text>`
    : `<text class="fb-name" x="${x}" y="${y + 5}">${name}</text>`
  const circle = `<circle cx="${x}" cy="${y}" r="${radius}"/>`
  return `<g class="fb-marker fb-${role}" data-string="${string}" data-fret="${fret}">${circle}${label}</g>`
}

// A fretboard as SVG markup, styled only by its classes: the strings of a tuning (MIDI notes, highest first, drawn top to
// bottom) with a marker at every position of each pitch class in `markers` (pitch class => { name, degree?, role })
export function fretboardSvg({ tuning, frets = 24, markers }) {
  const bottom = TOP + STRING_SPACING * (tuning.length - 1)
  const width = NUT + frets * FRET_WIDTH + 10
  const parts = [`<line class="fb-nut" x1="${NUT}" y1="${TOP}" x2="${NUT}" y2="${bottom}"/>`]

  for (let fret = 1; fret <= frets; fret++) {
    const x = NUT + fret * FRET_WIDTH
    parts.push(`<line class="fb-fret${fret % 12 === 0 ? ' fb-octave' : ''}" x1="${x}" y1="${TOP}" x2="${x}" y2="${bottom}"/>`)
    if (NUMBERED_FRETS.includes(fret % 12)) {
      parts.push(`<text class="fb-fret-number" x="${fretX(fret)}" y="${bottom + 32}">${fret}</text>`)
    }
  }

  tuning.forEach((open, i) => {
    const y = TOP + i * STRING_SPACING
    parts.push(`<line class="fb-string" x1="${NUT}" y1="${y}" x2="${width}" y2="${y}" stroke-width="${1.5 + i * 0.8}"/>`)
    parts.push(`<text class="fb-open-name" x="12" y="${y + 4}">${noteName(open)}</text>`)
    for (let fret = 0; fret <= frets; fret++) {
      const note = markers.get((open + fret) % 12)
      if (note) parts.push(marker(note, i + 1, fret, y))
    }
  })

  return `<svg class="fb" viewBox="0 0 ${width} ${bottom + 44}" xmlns="http://www.w3.org/2000/svg">${parts.join('')}</svg>`
}
