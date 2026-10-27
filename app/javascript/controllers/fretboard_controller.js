import { Controller } from "@hotwired/stimulus"
import { fretboardSvg } from "lib/fretboard"
import { WINDOW_RADIUS, analyzeScore, regionIndexAt, trackPitchClasses } from "lib/key_finder"
import { allKeys, keyName, noteName, scaleNotes } from "lib/scales"

const OPEN_KEY = "fretboard-open"
const MIN_FRETS = 24

// The fretboard panel in the player's dock: the displayed track's neck, marked with the scale of the key at the current bar.  The
// player controller drives it (see its fretboard outlet calls).
export default class extends Controller {
  static targets = ["panel", "toggle", "label", "key", "diagram"]

  connect() {
    this.regions = [{ start: 0, end: 1, key: null, candidates: [] }]
    this.track = null
    this.bar = 0
    this.override = null  // a key the user picked, as { key, region }, until the region changes
    this.setOpen(this.storedOpen())
  }

  // --- Called by the player ---

  loadScore(score) {
    this.regions = analyzeScore(score)
    this.region = null
    this.refresh()
  }

  showTrack(track, tuning, label) {
    this.track = track && { name: track.name, tuning, label, masks: trackPitchClasses(track), frets: this.fretsUsed(track) }
    this.refresh()
  }

  showBar(bar) {
    if (bar === this.bar) return
    this.bar = bar
    this.refresh()
  }

  // --- Actions ---

  toggle(e) {
    e.preventDefault()
    this.setOpen(this.panelTarget.hidden)
    try {
      localStorage.setItem(OPEN_KEY, this.panelTarget.hidden ? "0" : "1")
    } catch {
      // (private windows, blocked storage) the panel just won't stay open across reloads
    }
  }

  chooseKey() {
    const value = this.keyTarget.value
    if (value === "auto") {
      this.override = null
    } else {
      const [tonic, mode] = value.split(":")
      this.override = { key: { tonic: Number(tonic), mode }, region: this.region }
    }
    this.draw()
  }

  // --- Drawing ---

  setOpen(open) {
    this.panelTarget.hidden = !open
    this.toggleTarget.classList.toggle("active", open)
  }

  storedOpen() {
    try {
      return localStorage.getItem(OPEN_KEY) === "1"
    } catch {
      return false
    }
  }

  // Redraws for the current bar, rebuilding the key pulldown when its region changed
  refresh() {
    const region = regionIndexAt(this.regions, this.bar)
    if (region !== this.region) {
      this.region = region
      if (this.override && this.override.region !== region) this.override = null
      this.fillKeys()
    }
    this.draw()
  }

  fillKeys() {
    const { key, candidates } = this.regions[this.region]
    const select = this.keyTarget
    select.replaceChildren(new Option(`Auto: ${key ? keyName(key) : "no key"}`, "auto"))
    for (const candidate of candidates) {
      select.add(new Option(`${keyName(candidate)} · ${Math.round(candidate.score * 100)}%`, this.keyValue(candidate)))
    }
    const all = allKeys()
    for (let tonic = 0; tonic < 12; tonic++) {
      const keys = all.filter(k => k.tonic === tonic)
      const group = document.createElement("optgroup")
      group.label = keyName(keys[0]).split(" ")[0]
      group.append(...keys.map(k => new Option(keyName(k), this.keyValue(k))))
      select.add(group)
    }
    select.value = this.override ? this.keyValue(this.override.key) : "auto"
  }

  keyValue(key) {
    return `${key.tonic}:${key.mode}`
  }

  draw() {
    if (!this.track) {
      this.labelTarget.textContent = ""
      this.diagramTarget.textContent = "No guitar or bass track selected"
      return
    }
    this.labelTarget.textContent = `${this.track.name} · ${this.track.label}`
    const key = this.override?.key ?? this.regions[this.region].key
    this.diagramTarget.innerHTML = fretboardSvg({ tuning: this.track.tuning, frets: this.track.frets, markers: this.markers(key) })
  }

  // The scale's notes, and the other pitch classes the track plays around the current bar (all of them if there's no key)
  markers(key) {
    const markers = new Map(key ? scaleNotes(key).map(note => [note.pitchClass, note]) : [])
    const played = this.track.masks
      .slice(Math.max(0, this.bar - WINDOW_RADIUS), this.bar + WINDOW_RADIUS + 1)
      .reduce((all, mask) => all | mask, 0)
    for (let pc = 0; pc < 12; pc++) {
      if (played & (1 << pc) && !markers.has(pc)) {
        markers.set(pc, { name: noteName(pc, key), role: key ? "chromatic" : "note" })
      }
    }
    return markers
  }

  fretsUsed(track) {
    return track.staves
      .flatMap(staff => staff.bars.flatMap(bar => bar.voices.flatMap(voice => voice.beats.flatMap(beat => beat.notes))))
      .reduce((most, note) => Math.max(most, note.fret), MIN_FRETS)
  }
}
