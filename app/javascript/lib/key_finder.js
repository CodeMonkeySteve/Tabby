import { MODES, MODE_OFFSETS } from 'lib/scales'

// Bars on each side of a bar in its detection window
export const WINDOW_RADIUS = 2

// Quarter notes a window needs to call its note set
const MIN_WEIGHT = 2

// The least share of a region's notes its note set must hold for it to have a key at all
const MIN_FIT = 0.8

// How much better another note set must fit, for how many bars in a row, to change the key
const SWITCH_MARGIN = 0.08
const MIN_REGION_BARS = 4

// How many bars a detected key change moves to reach a section start, where key changes mostly fall
const SECTION_REACH = 2

// How much a note's sounding duration counts as evidence for it being the home note, when it's the lowest note at its start,
// on a strong beat, or starts or ends a phrase
const BASS = 1.5
const STRONG = 1
const EDGE = 1

const QUARTER = 960  // MIDI ticks

const pitchClass = n => ((n % 12) + 12) % 12

// The 12 diatonic note sets, by their major (Ionian) root
const SETS = Array.from({ length: 12 }, (_, root) => new Set(MODE_OFFSETS.map(offset => pitchClass(root + offset))))

const sum = values => values.reduce((total, value) => total + value, 0)
const addUp = (bars, field) => Array.from({ length: 12 }, (_, pc) => sum(bars.map(bar => bar[field][pc])))

// The share of weights in a note set
function fit(weights, root) {
  const total = sum(weights)
  return total > 0 ? sum(weights.filter((_, pc) => SETS[root].has(pc))) / total : 0
}

const roots = [...SETS.keys()]
const bestRoot = (weights, tieBreak) =>
  roots.reduce((best, root) => {
    const [a, b] = [fit(weights, root), fit(weights, best)]
    return a > b || (a === b && fit(tieBreak, root) > fit(tieBreak, best)) ? root : best
  })

const normalized = candidates => {
  const total = sum(candidates.map(c => c.score))
  return candidates
    .map(c => ({ ...c, score: total > 0 ? c.score / total : 1 / candidates.length }))
    .sort((a, b) => b.score - a.score)
}

const modeOf = (tonic, root) => MODES[MODE_OFFSETS.indexOf(pitchClass(tonic - root))]

// Note sets fitting within this much of the best are ties, decided by how common their mode is
const TIE = 0.02
const MODE_PRIOR = ['aeolian', 'ionian', 'mixolydian', 'dorian', 'phrygian', 'lydian', 'locrian']

// Raises the note sets' fits to a power before normalizing them, so a set fitting well ranks clearly ahead
const SHARPNESS = 16

// How much better the mirrored signature's set must fit to be taken instead (see signatureRegion)
const MIRROR_MARGIN = 0.1

const regionKey = (start, end, candidates) =>
  ({ start, end, key: { tonic: candidates[0].tonic, mode: candidates[0].mode }, candidates })

const noKey = (start, end) => ({ start, end, key: null, candidates: [] })

const rankTonics = (cues, root) =>
  normalized(MODE_OFFSETS.map(offset => {
    const tonic = pitchClass(root + offset)
    return { tonic, mode: modeOf(tonic, root), score: cues[tonic] }
  }))

// A detected region's key: the note set's tonic with the most home-note evidence
function detectedRegion(bars, start, end, root) {
  const weights = addUp(bars.slice(start, end), 'weights')
  const cues = addUp(bars.slice(start, end), 'cues')
  const { tonic } = rankTonics(cues, root)[0]
  const holding = roots.filter(r => SETS[r].has(tonic))
  const best = Math.max(...holding.map(r => fit(weights, r)))
  const tied = holding.filter(r => fit(weights, r) >= best - TIE)
  const chosen = tied.reduce((a, b) => (MODE_PRIOR.indexOf(modeOf(tonic, b)) < MODE_PRIOR.indexOf(modeOf(tonic, a)) ? b : a))
  return fit(weights, chosen) < MIN_FIT ? noKey(start, end) : regionKey(start, end, rankTonics(cues, chosen))
}

// A score key signature's region: its home note, in the mode whose note set fits the notes best.  Some scores' flat keys read
// as sharp keys (A♭ major as E major), so the mirrored signature is taken when its set fits clearly better, and the notes'
// own set is detected when the home note isn't even in it.  A tonic with more home-note evidence than the marked one is needed
// too, since a song may borrow its notes from another set (G Dorian is F major's set).
function signatureRegion(bars, start, end, signature = bars[start].signature) {
  const { id, tonic: marked } = signature
  const [sharps, type] = id.split('/').map(Number)
  const weights = addUp(bars.slice(start, end), 'weights')
  if (sum(weights) < MIN_WEIGHT) return noKey(start, end)
  const cues = addUp(bars.slice(start, end), 'cues')
  const best = bestRoot(weights, weights)
  const mirrored = pitchClass(-7 * sharps)
  const mirroredTonic = pitchClass(mirrored + (type === 1 ? 9 : 0))
  const flipped = fit(weights, mirrored) >= fit(weights, best) - MIRROR_MARGIN &&
    fit(weights, mirrored) > fit(weights, pitchClass(7 * sharps)) + MIRROR_MARGIN &&
    cues[mirroredTonic] > cues[marked]
  const tonic = flipped ? mirroredTonic : marked
  if (!SETS[best].has(tonic)) return detectedRegion(bars, start, end, best)

  return regionKey(start, end, normalized(MODES.map((mode, i) => (
    { tonic, mode, score: fit(weights, pitchClass(tonic - MODE_OFFSETS[i])) ** SHARPNESS }
  ))))
}

// Regions from spans of bars, joining neighbors whose keys `joins` says aren't a key change (by default the same key, as
// neighboring note sets can tie into one key, see detectedRegion, and differently marked score keys can be one key), unless
// together they've no key
function joinedRegions(spans, regionOf, joins = sameKey) {
  const regions = []
  const joinLast = () => {
    const [previous, last] = regions.slice(-2)
    const span = { ...previous.span, end: last.span.end }
    const region = regionOf(span)
    if (!region.key && last.region.key) return false
    regions.splice(-2, 2, { span, region })
    return true
  }
  const joinsLast = () => regions.length > 1 && joins(regions.at(-2).region.key, regions.at(-1).region.key, regions.at(-1).span)
  for (const span of spans) {
    regions.push({ span, region: regionOf(span) })
    while (joinsLast() && joinLast());  // a joined region's key may join it to its previous neighbor too
  }
  return regions.map(({ region }) => region)
}

const sameKey = (a, b) => a === b || (a && b && a.tonic === b.tonic && a.mode === b.mode)

// The runs of a score's key signatures, with runs too sparse to call (count-ins, rests) joined to a neighbor
function signatureRegions(bars) {
  const spans = []
  bars.forEach((bar, i) => {
    if (i === 0 || bar.signature.id !== bars[i - 1].signature.id) spans.push({ start: i, end: i + 1 })
    else spans.at(-1).end = i + 1
  })
  const sparse = ({ start, end }) => sum(addUp(bars.slice(start, end), 'weights')) < MIN_WEIGHT
  const called = []
  for (const { start, end } of spans) {
    const previous = called.at(-1)
    if (previous && sparse({ start, end })) previous.end = end
    else if (previous && sparse(previous)) Object.assign(previous, { end, signature: bars[start].signature })
    else called.push({ start, end, signature: bars[start].signature })
  }
  return joinedRegions(called, ({ start, end, signature }) => signatureRegion(bars, start, end, signature))
}

// Each bar's window weights, or null if too sparse to call
function windows(bars) {
  return bars.map((_, i) => {
    const weights = addUp(bars.slice(Math.max(0, i - WINDOW_RADIUS), i + WINDOW_RADIUS + 1), 'weights')
    return sum(weights) >= MIN_WEIGHT ? weights : null
  })
}

// The bars where the note set changes, and the set from each, starting with bar 0
function setChanges(bars) {
  const song = addUp(bars, 'weights')
  const windowed = windows(bars)
  const first = windowed.find(Boolean)
  const changes = [[0, bestRoot(first, song)]]
  let streak = null
  windowed.forEach((weights, i) => {
    if (!weights) return
    const current = changes.at(-1)[1]
    const best = bestRoot(weights, song)
    if (best === current || fit(weights, best) - fit(weights, current) < SWITCH_MARGIN) {
      streak = null
      return
    }
    if (streak?.root !== best) streak = { root: best, start: i, length: 0 }
    if (++streak.length < MIN_REGION_BARS) return

    // windows blur where the set changed (either way), so start the region at the first bar whose own notes fit the new set better
    const from = Math.max(changes.at(-1)[0] + 1, streak.start - WINDOW_RADIUS)
    const to = Math.min(bars.length, streak.start + WINDOW_RADIUS + 1)
    const start = Array.from({ length: to - from }, (_, i) => from + i)
      .find(b => fit(bars[b].weights, best) > fit(bars[b].weights, current)) ?? streak.start
    const leaning = b => fit(bars[b].weights, best) - fit(bars[b].weights, current)
    const snapped = sectionStartNear(bars, start, changes.at(-1)[0], leaning)
    if (snapped - changes.at(-1)[0] >= MIN_REGION_BARS) changes.push([snapped, best])
    else if (changes.at(-2)?.[1] === best) changes.pop()  // a passage too short to be a key change
    else changes.at(-1)[1] = best
    streak = null
  })
  if (changes.length > 1 && bars.length - changes.at(-1)[0] < MIN_REGION_BARS) changes.pop()
  return changes
}

// The nearest section start within reach of a bar where a set changes and after another, past no bars that clearly belong where
// they are: earlier bars to the old set, or later ones to the new (by how much better they fit the new set, `leaning`)
function sectionStartNear(bars, bar, after, leaning) {
  const between = (a, b) => Array.from({ length: Math.abs(b - a) }, (_, i) => Math.min(a, b) + i)
  const movable = start => between(start, bar).every(b => (start < bar ? leaning(b) > -SWITCH_MARGIN : leaning(b) < SWITCH_MARGIN))
  for (let distance = 0; distance <= SECTION_REACH; distance++) {
    const start = [bar - distance, bar + distance].find(b => b > after && b < bars.length && bars[b].section && movable(b))
    if (start !== undefined) return start
  }
  return bar
}

const setOf = key => pitchClass(key.tonic - MODE_OFFSETS[MODES.indexOf(key.mode)])

// A change of mode alone is more likely borrowed chords than a key change, and one of home note alone is the same notes, unless
// a section starts there
const continuesWithin = bars => (a, b, span) =>
  sameKey(a, b) || (a && b && (a.tonic === b.tonic || setOf(a) === setOf(b)) && !bars[span.start].section)

export function findKeys(bars) {
  if (bars.some(bar => bar.signature)) return signatureRegions(bars)

  if (!windows(bars).some(Boolean)) return [noKey(0, bars.length)]
  const changes = setChanges(bars)
  const spans = changes.map(([start, root], i) => ({ start, end: changes[i + 1]?.[0] ?? bars.length, root }))
  return joinedRegions(spans, ({ start, end, root }) => detectedRegion(bars, start, end, root), continuesWithin(bars))
}

export function regionIndexAt(regions, bar) {
  let [low, high] = [0, regions.length - 1]
  while (low < high) {
    const middle = Math.ceil((low + high) / 2)
    if (regions[middle].start <= bar) low = middle
    else high = middle - 1
  }
  return low
}

// A staff voice's sounding beats in order, as { beat, start, end }
function voiceBeats(staff, voiceIndex) {
  return staff.bars
    .flatMap(bar => bar.voices[voiceIndex]?.beats ?? [])
    .filter(beat => !beat.isRest && beat.notes.some(note => !note.isDead))
    .map(beat => ({ beat, start: beat.absolutePlaybackStart, end: beat.absolutePlaybackStart + beat.playbackDuration }))
}

// Every sounding note of the score's pitched staves, with its timing and phrase position
function soundingNotes(score) {
  const notes = []
  for (const staff of score.tracks.flatMap(track => track.staves).filter(staff => !staff.isPercussion)) {
    const voiceCount = Math.max(0, ...staff.bars.map(bar => bar.voices.length))
    for (let v = 0; v < voiceCount; v++) {
      const beats = voiceBeats(staff, v)
      beats.forEach(({ beat, start, end }, i) => {
        const edge = i === 0 || start - beats[i - 1].end >= QUARTER || i === beats.length - 1 || beats[i + 1].start - end >= QUARTER
        for (const note of beat.notes.filter(note => !note.isDead)) {
          notes.push({ note, beat, start, end, edge, bar: beat.voice.bar.index, pitch: note.realValue })
        }
      })
    }
  }
  return notes
}

// How strongly a beat falls in its bar: 1 on the downbeat, 0.5 halfway through a bar of an even number of beats, else 0
function strength(beat) {
  const masterBar = beat.voice.bar.masterBar
  if (beat.playbackStart === 0) return 1
  return masterBar.timeSignatureNumerator % 2 === 0 && beat.playbackStart * 2 === masterBar.calculateDuration() ? 0.5 : 0
}

function signatureOf(masterBar) {
  const { keySignature, keySignatureType } = masterBar
  return { id: `${keySignature}/${keySignatureType}`, tonic: pitchClass(keySignature * 7 + (keySignatureType === 1 ? 9 : 0)) }
}

// Per master bar, the score's pitch-class weights and home-note cues (see findKeys), its key signature if it has any, and whether
// a section starts there
export function barData(score) {
  const signed = score.masterBars.some(bar => bar.keySignature !== 0 || bar.keySignatureType !== 0)
  const bars = score.masterBars.map(masterBar => ({
    weights: Array(12).fill(0),
    cues: Array(12).fill(0),
    signature: signed ? signatureOf(masterBar) : null,
    section: Boolean(masterBar.section),
  }))

  const notes = soundingNotes(score)
  const lowest = new Map()
  for (const { start, pitch } of notes) lowest.set(start, Math.min(pitch, lowest.get(start) ?? Infinity))
  const first = notes.reduce((earliest, { start }) => Math.min(earliest, start), Infinity)
  const last = notes.reduce((latest, { start }) => Math.max(latest, start), -Infinity)

  for (const { note, beat, start, end, edge, bar, pitch } of notes) {
    const quarters = (end - start) / QUARTER
    const attack = !note.isTieDestination
    const bass = lowest.get(start) === pitch ? BASS : 0
    const accent = attack ? STRONG * strength(beat) : 0
    const phrase = attack && (edge || start === first || start === last) ? EDGE : 0
    bars[bar].weights[pitchClass(pitch)] += quarters
    bars[bar].cues[pitchClass(pitch)] += quarters * (1 + bass + accent) + phrase
  }
  return bars
}

export function analyzeScore(score) {
  return findKeys(barData(score))
}

// Per master bar, a 12-bit mask of the pitch classes (bit 0 is C) a track sounds
export function trackPitchClasses(track) {
  const masks = Array(track.score.masterBars.length).fill(0)
  for (const staff of track.staves.filter(staff => !staff.isPercussion)) {
    for (const bar of staff.bars) {
      for (const voice of bar.voices) {
        for (const beat of voice.beats) {
          for (const note of beat.notes.filter(note => !note.isDead)) masks[bar.index] |= 1 << pitchClass(note.realValue)
        }
      }
    }
  }
  return masks
}
