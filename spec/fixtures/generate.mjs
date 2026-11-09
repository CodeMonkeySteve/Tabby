// Generates the fixtures derived from "Practice Etude.alphatex": node spec/fixtures/generate.mjs
//   Practice Etude.gp      the etude's bass part, as Guitar Pro 7
//   songsterr/             the etude as a Songsterr song: its page, parts (with a guitar and drums added), and video points
import { readFileSync, writeFileSync } from 'node:fs'
import { gzipSync } from 'node:zlib'
import * as alphaTab from '../../lib/alpha_tab/node_modules/@coderline/alphatab/dist/alphaTab.mjs'

const fixture = (name) => new URL(name, import.meta.url)
const writeJson = (name, data) => writeFileSync(fixture(name), `${JSON.stringify(data)}\n`)

const settings = new alphaTab.Settings()
const importer = new alphaTab.importer.AlphaTexImporter()
importer.initFromString(readFileSync(fixture('Practice Etude.alphatex'), 'utf8'), settings)
const score = importer.readScore()
writeFileSync(fixture('Practice Etude.gp'), new alphaTab.exporter.Gp7Exporter().export(score, settings))

// --- Songsterr ---

const SONG_ID = 1001
const REVISION_ID = 2002
const IMAGE = 'v4-1-1-PracticeEtude'
const CLOUDFRONT_HOST = 'd111111abcdef8.cloudfront.net'
const TEMPO = score.tempo
const SECONDS_PER_BAR = (60 / TEMPO) * 4

const KEY_SIGNATURES = { 0: { accidentalCount: 1, mode: 'major', transposeAs: '#' },
  8: { accidentalCount: 3, mode: 'major', transposeAs: '#' },
  16: { accidentalCount: 1, mode: 'major', transposeAs: '#' } }
// The root of each bar's chord, as a [string, fret] of a power chord on the guitar (Songsterr strings count from the highest, 0)
const ROOTS = { A: [4, 0], C: [4, 3], D: [4, 5], E: [5, 0], 'F#': [5, 2], G: [5, 3] }
const CHORDS = ['A', 'D', 'G', 'G', 'C', 'D', 'E', 'D', 'A', 'D', 'E', 'A', 'F#', 'D', 'E', 'E',
  'G', 'C', 'D', 'G', 'E', 'C', 'D', 'G']
const SLIDES = { [alphaTab.model.SlideOutType.Shift]: 'shift', [alphaTab.model.SlideOutType.Legato]: 'legato' }

const beat = (type, notes) => ({ notes, type, duration: [1, type] })

function measure(index, beats) {
  return { ...(index === 0 && { signature: [4, 4] }), ...(KEY_SIGNATURES[index] && { keySignature: KEY_SIGNATURES[index] }),
    voices: [{ beats }] }
}

const bassMeasures = score.tracks[0].staves[0].bars.map((bar) => measure(bar.index, bar.voices[0].beats.map((b) =>
  beat(b.duration, b.notes.map((note) => ({
    fret: note.fret, string: 4 - note.string,
    ...(note.isTieDestination && { tie: true }), ...(note.isHammerPullOrigin && { hp: true }),
    ...(SLIDES[note.slideOutType] && { slide: SLIDES[note.slideOutType] }), ...(note.isDead && { dead: true }),
  }))))))

const guitarMeasures = CHORDS.map((chord, index) => {
  const [string, fret] = ROOTS[chord]
  const notes = [{ fret, string }, { fret: fret + 2, string: string - 1 }, { fret: fret + 2, string: string - 2 }]
  const last = index === CHORDS.length - 1
  return measure(index, last ? [beat(1, notes)] : Array.from({ length: 8 }, () => beat(8, notes)))
})

const [HI_HAT, KICK, SNARE, CRASH] = [{ fret: 42, string: -0.5 }, { fret: 36, string: 3.5 }, { fret: 38, string: 1.5 },
  { fret: 49, string: -1 }]
const drumMeasures = CHORDS.map((_chord, index) => {
  if (index === CHORDS.length - 1) return measure(index, [beat(1, [CRASH, KICK])])
  return measure(index, Array.from({ length: 8 }, (_, eighth) =>
    beat(8, [HI_HAT, ...(eighth % 4 === 0 ? [KICK] : []), ...(eighth % 4 === 2 ? [SNARE] : [])])))
})

const TRACKS = [
  { instrumentId: 30, instrument: 'Distortion Guitar', tuning: [64, 59, 55, 50, 45, 40], hash: 'guitar_EtudeGtr1', isGuitar: true,
    measures: guitarMeasures },
  { instrumentId: 33, instrument: 'Electric Bass (finger)', tuning: [43, 38, 33, 28], hash: 'bass_EtudeBas1', isBassGuitar: true,
    measures: bassMeasures },
  { instrumentId: 1024, instrument: 'Drums', hash: 'drums_EtudeDrm1', isDrums: true, measures: drumMeasures },
]

function part({ instrumentId, instrument, tuning, measures }, partId) {
  return {
    name: '', balance: 0, volume: 1, measures, frets: 24, ...(tuning ? { tuning } : { tuningFlat: true }),
    strings: tuning?.length ?? 6, instrumentId, instrument, newLyrics: [], partId,
    automations: { tempo: [{ measure: 0, position: 0, bpm: TEMPO, type: 4, visible: false }] },
    version: 8, songId: SONG_ID, revisionId: REVISION_ID,
  }
}

const parts = TRACKS.map(part)
parts.forEach((data, partId) => writeFileSync(fixture(`songsterr/${partId}.json.gz`), gzipSync(JSON.stringify(data))))

// The bass's first 6 bars, repeating bars 2–4 with alternate endings: bars 1, 2, 3, 4, 2, 3, 5, 6 are played
const repeats = part(TRACKS[1], 1)
repeats.measures = repeats.measures.slice(0, 6).map((m) => ({ ...m }))
Object.assign(repeats.measures[1], { repeatStart: true })
Object.assign(repeats.measures[3], { alternateEnding: [1], repeat: 2 })
Object.assign(repeats.measures[4], { alternateEnding: [2] })
writeJson('songsterr/repeats.json', repeats)

const VIDEOS = [
  { id: 3001, status: 'done', feature: null, videoId: 'EtudeOrigin' },
  { id: 3002, status: 'done', feature: 'alternative', videoId: 'EtudeAltern' },
  { id: 3003, status: 'done', feature: 'solo', videoId: 'EtudeSolo01' },
  { id: 3004, status: 'done', feature: 'backing', videoId: 'EtudeBack01' },
]

const current = {
  aiGenerated: true, fingerstyle: false, createdAt: '2026-01-01T00:00:00.000Z', revisionId: REVISION_ID, songId: SONG_ID,
  artist: score.artist, artistId: 4001, title: score.title,
  author: { personId: 5001, name: 'etude-transcriber', profileName: 'etude-transcriber', isModerator: false },
  description: 'Initial revision', hasPlayer: true, hasTracks: true, hasChords: false,
  tracks: TRACKS.map(({ instrumentId, instrument, tuning, hash, isGuitar, isBassGuitar, isDrums }, partId) => ({
    instrumentId, instrument, views: 10, name: '', ...(tuning && { tuning }), difficulty: 2, hash, isVocalTrack: false,
    isEmpty: false, title: instrument, partId, isDrums: !!isDrums, isBassGuitar: !!isBassGuitar, isGuitar: !!isGuitar,
    isPiano: false, originalPartId: partId,
  })),
  defaultTrack: 1, popularTrack: 1, isPublished: true, isBlank: false, isJunk: false, videos: VIDEOS,
  popularTrackGuitar: 0, popularTrackBass: 1, popularTrackDrum: 2, latestRevisionId: REVISION_ID,
  tags: ['etude', 'exercise', 'practice'], image: IMAGE, partId: 1,
}
const state = { meta: { current, songId: SONG_ID, partId: 1, revisionId: REVISION_ID } }
writeFileSync(fixture('songsterr/page.html'), `<!DOCTYPE html>
<html>
<head>
<title>Practice Etude Bass Tab by Tabby | Songsterr Tabs with Rhythm</title>
<link rel="dns-prefetch" href="//www.google-analytics.com/">
<link rel="dns-prefetch" href="//${CLOUDFRONT_HOST}/">
</head>
<body>
<script id="state" type="application/json">${JSON.stringify(state)}</script>
</body>
</html>
`)

// A sync point at the start of each bar; the alternative recording starts later
const points = (offset) => CHORDS.map((_chord, bar) => Math.round((offset + bar * SECONDS_PER_BAR) * 100) / 100)
writeJson('songsterr/video_points.json', VIDEOS.filter((video) => video.feature !== 'solo').map((video) => ({
  id: video.id, revisionToVideoId: video.id + 1000, songId: SONG_ID, revisionId: REVISION_ID,
  points: points(video.feature === 'alternative' ? 0.75 : 0), videoId: video.videoId, status: 'done', feature: video.feature,
  tracks: video.feature === 'backing' ? [2] : null,
})))
