import assert from 'node:assert/strict'
import { test } from 'node:test'
import { fretboardSvg } from 'lib/fretboard'

const BASS = [43, 38, 33, 28]
const count = (svg, pattern) => (svg.match(pattern) ?? []).length

test('draws strings, frets, and markers for every matching position', () => {
  const markers = new Map([[2, { name: 'D', degree: '1', role: 'root' }], [5, { name: 'F', role: 'chromatic' }]])
  const svg = fretboardSvg({ tuning: BASS, markers })
  assert.match(svg, /^<svg class="fb" viewBox="0 0 \d+ \d+"/)
  assert.equal(count(svg, /class="fb-string"/g), 4)
  assert.equal(count(svg, /class="fb-fret( fb-octave)?"/g), 24)
  assert.equal(count(svg, /fb-octave/g), 2)
  assert.equal(count(svg, /class="fb-fret-number"/g), 10)
  // D on the G string at 7 and 19, the D string at 0, 12, and 24, the A string at 5 and 17, and the E string at 10 and 22
  assert.equal(count(svg, /fb-marker fb-root/g), 9)
  assert.match(svg, /fb-marker fb-root" data-string="2" data-fret="0"/)
  assert.match(svg, /fb-marker fb-chromatic" data-string="4" data-fret="1"/)
  assert.equal(count(svg, /class="fb-degree"/g), 9)  // none on chromatic markers
})

test('draws a 5-string bass and extends past 24 frets', () => {
  const svg = fretboardSvg({ tuning: [43, 38, 33, 28, 23], frets: 27, markers: new Map() })
  assert.equal(count(svg, /class="fb-string"/g), 5)
  assert.equal(count(svg, /class="fb-fret( fb-octave)?"/g), 27)
  assert.deepEqual([...svg.matchAll(/class="fb-open-name"[^>]*>([^<]+)</g)].map(m => m[1]), ['G', 'D', 'A', 'E', 'B'])
})

test('has no colors', () => {
  const svg = fretboardSvg({ tuning: BASS, markers: new Map([[2, { name: 'D', degree: '1', role: 'root' }]]) })
  assert.doesNotMatch(svg, /fill="|stroke="|#[0-9a-f]{3,6}\b|style=/i)
})
