// A fingering optimizer that moves the fretting hand least, playing one finger per fret.  It steps through the beats, extending
// each of the cheapest partial fingerings with every way to play the next beat, and keeps the cheapest of those.

export const DEFAULTS = {
  beamWidth: 200,      // partial fingerings kept after each beat
  yieldEvery: 250,     // beats between letting other work (like the page) run
  handSpan: 4,         // frets the hand covers without stretching
  maxSpan: 5,          // frets a beat's fretted notes may span
  shiftBase: 2,        // cost of moving the hand
  shiftPerFret: 1,     // added cost per fret moved
  stretch: 3,          // cost per fret stretched beyond the hand span
  ringCut: 1,          // cost of playing a string while another note on it rings
  positionBias: 0.01,  // cost per fret of a new hand position, preferring lower positions when otherwise equal
  repeatMove: 3,       // cost of playing a note on another string than the previous beat's note of the same pitch
  octaveReach: 2,      // strings an octave may be played above (or below) the previous beat's note without cost
  octaveMove: 3,       // cost of playing an octave beyond the reach of the previous beat's note
}

// Resolves to the string of each note of a fingering problem (see TrackTab#problem) by index, or null if they can't all be played
export default async function beam(problem, options = {}) {
  const o = { ...DEFAULTS, ...options }
  const { notes, beats } = problem
  const chainEnds = new Map()  // the last beat of each chain
  for (const note of notes) chainEnds.set(note.chain, Math.max(chainEnds.get(note.chain) ?? -1, note.beat))
  const links = beats.map((beat, b) => beatLinks(b > 0 ? beats[b - 1] : null, beat, notes, o))
  const linked = beats.map((_, b) => linkedNotes(links[b + 1]))

  let states = [{ hand: null, locks: new Map(), ringing: new Map(), cost: 0, parent: null, strings: [] }]
  for (const [b, beat] of beats.entries()) {
    const beatNotes = beat.notes.map(i => notes[i])
    const choices = beatChoices(beatNotes, o)
    const next = new Map()  // the cheapest state by key
    for (const state of states) {
      for (const choice of choices) {
        for (const extended of extend(state, beat, beatNotes, choice, links[b], o)) {
          updateLocks(extended.locks, beatNotes, choice, chainEnds, b)
          const key = stateKey(extended, linked[b])
          if (!(next.get(key)?.cost <= extended.cost)) next.set(key, extended)
        }
      }
    }
    states = [...next.values()].sort((x, y) => x.cost - y.cost).slice(0, o.beamWidth)
    if (states.length === 0) return null
    if (b % o.yieldEvery === o.yieldEvery - 1) await new Promise(resolve => setTimeout(resolve))
  }
  return fingering(states[0], beats, notes.length)
}

// Every way to play a beat's notes: a position for each, on different strings, within the maximum span
function beatChoices(beatNotes, o) {
  const choices = []
  const choose = (chosen, used) => {
    if (chosen.length === beatNotes.length) {
      const frets = frettedFrets(beatNotes, chosen)
      if (frets.length === 0 || Math.max(...frets) - Math.min(...frets) < o.maxSpan) choices.push(chosen)
      return
    }
    for (const position of beatNotes[chosen.length].positions) {
      if (!used.has(position.string)) choose([...chosen, position], new Set(used).add(position.string))
    }
  }
  choose([], new Set())
  return choices
}

// The frets the hand must cover (not open strings or free notes)
function frettedFrets(beatNotes, choice) {
  return choice.flatMap((position, j) => (position.fret > 0 && !beatNotes[j].free ? [position.fret] : []))
}

const clamp = (value, min, max) => Math.min(Math.max(value, min), max)

// How each of a beat's notes is biased by the previous beat's (by index in the beat), or null if not: toward the strings of
// notes of the same pitch, or else within reach of the strings of notes an octave away, as the offsets (from the previous
// note's string) allowed without cost
function beatLinks(previous, beat, notes, o) {
  if (!previous) return []
  const others = previous.notes.map(i => notes[i])
  return beat.notes.map(i => {
    const { pitch, free } = notes[i]
    if (free) return null
    const links = (interval, min, max) => others
      .flatMap((other, k) => (!other.free && other.pitch + interval === pitch ? [{ k, min, max }] : []))
    const same = links(0, 0, 0)
    if (same.length > 0) return { targets: same, cost: o.repeatMove }
    const octaves = [...links(12, -Infinity, o.octaveReach), ...links(-12, -o.octaveReach, Infinity)]
    return octaves.length > 0 ? { targets: octaves, cost: o.octaveMove } : null
  })
}

// The indexes (in the previous beat) of the notes a beat's links are biased by
function linkedNotes(links = []) {
  return [...new Set(links.flatMap(link => link?.targets.map(target => target.k) ?? []))].sort((a, b) => a - b)
}

// The states after playing a beat's choice of positions: none if it breaks a chain's string, else one per hand position
// covering it
function extend(state, beat, beatNotes, choice, links, o) {
  let cost = state.cost
  const ringing = new Map([...state.ringing].filter(([, ring]) => ring.end > beat.start))
  for (const [j, { string }] of choice.entries()) {
    const { chain } = beatNotes[j]
    const lock = state.locks.get(chain)
    if (lock !== undefined && lock !== string) return []
    if ((ringing.get(string)?.chain ?? chain) !== chain) cost += o.ringCut
    ringing.set(string, { end: beat.end, chain })
    const link = links[j]
    if (link && !link.targets.some(({ k, min, max }) => string - state.strings[k] >= min && string - state.strings[k] <= max)) {
      cost += link.cost
    }
  }

  const frets = frettedFrets(beatNotes, choice)
  const strings = choice.map(position => position.string)
  const result = (hand, extra = 0) => ({ hand, locks: new Map(state.locks), ringing, cost: cost + extra, parent: state, strings })
  if (frets.length === 0) return [result(state.hand)]

  const lo = Math.min(...frets)
  const hi = Math.max(...frets)
  const stretch = o.stretch * Math.max(0, hi - lo + 1 - o.handSpan)
  if (state.hand !== null && lo >= state.hand && hi < state.hand + o.handSpan) return [result(state.hand, stretch)]

  // the hand positions covering the frets (or starting at the lowest, when stretching)
  const lowest = clamp(hi - o.handSpan + 1, 1, lo)
  const hands = Array.from({ length: lo - lowest + 1 }, (_, k) => lowest + k)
  return hands.map(hand => {
    const shift = state.hand === null ? 0 : o.shiftBase + o.shiftPerFret * Math.abs(hand - state.hand)
    return result(hand, stretch + shift + o.positionBias * hand)
  })
}

// Locks the strings of chains continuing after this beat, and unlocks finished chains
function updateLocks(locks, beatNotes, choice, chainEnds, b) {
  for (const [j, { string }] of choice.entries()) {
    const { chain } = beatNotes[j]
    if (chainEnds.get(chain) > b) locks.set(chain, string)
  }
  for (const chain of locks.keys()) {
    if (chainEnds.get(chain) <= b) locks.delete(chain)
  }
}

// States with the same hand position, locked strings, and strings of the notes the next beat's are biased by play the rest of
// the beats alike (but for any ringing notes they'd cut off, a small cost, ignored here so ringing chords don't keep every state
// apart), so only the cheapest is kept
function stateKey(state, linked) {
  const locks = [...state.locks].map(([chain, string]) => `${chain}=${string}`).sort()
  return `${state.hand}|${locks}|${linked.map(k => state.strings[k])}`
}

// The strings by note index, following the final state's parents back through the beats
function fingering(state, beats, count) {
  const strings = new Array(count).fill(null)
  for (let b = beats.length - 1; state.parent; b--, state = state.parent) {
    beats[b].notes.forEach((i, j) => { strings[i] = state.strings[j] })
  }
  return strings
}
