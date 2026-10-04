import { Controller } from "@hotwired/stimulus"
import * as alphaTab from "@coderline/alphatab"
import AlternateTabs from "lib/alternate_tabs"
import { DEFAULT_OPTIMIZER, optimizers } from "lib/fingering"
import TrackTab from "lib/track_tab"
import TabEditor from "lib/tab_editor"
import { noteNames, tuningGroups } from "lib/tunings"

export default class extends Controller {
  static values = {
    song: Object,
    previousUrl: String,  // the player of the previous song in the playlist being played, if any
  }

  static outlets = ["sync-editor"]

  static targets = [
    "canvas", "dock", "trackList", "trackPanel", "playerLoading",
    "songTitle", "songArtist", "timePosition", "timeSliderValue",
    "playPause", "countIn", "metronome", "loop", "tabEdit",
    "speedLabel", "speedSlider", "zoomLabel", "zoomSlider", "trackTemplate",
    "volumeLabel", "volumeSlider", "volumeIcon", "osd", "osdIcon", "osdText",
  ]

  connect() {
    this.trackItems = []
    this.currentTempo = 0
    this.previousTime = -1
    this.playStartedAt = null      // Date.now() when playback begins, null otherwise
    this.accumulatedSeconds = 0    // running total of wall-clock seconds played
    this.playDate = null           // ISO date (YYYY-MM-DD) of first play start this session
    this.historyTimer = null       // debounce timer handle
    this.note = this.songValue.note ?? {}  // the user's latest player settings for the song
    this.trackTunings = { ...this.note.track_tunings }  // the chosen tuning of each track not in the score's, by track index
    this.trackTabs = new Map()     // the stringed tracks' TrackTab, by track index (once the score loads)
    this.alternateTabs = new AlternateTabs(this.songValue.id, this.songValue.alternateTabs, {
      onError: tab => this.showTuningMessage(tab.trackIndex, "Couldn't save your tab changes"),
    })
    this.savedNote = null          // JSON of the last saved (or restored) note, null until the saved note is applied
    this.noteTimer = null          // debounce timer handle
    this.rangeRestored = false
    this.unloadHandler = () => {
      this.flushHistory()
      this.flushNote()
      this.alternateTabs.flush({ keepalive: true })
    }
    window.addEventListener('beforeunload', this.unloadHandler)

    this.keyHandler = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.keyHandler)

    const zoom = this.restoreZoom()
    this.api = new alphaTab.AlphaTabApi(this.canvasTarget, {
      file: `/s/${this.songValue.id}/score`,
      core: { includeNoteBounds: true },  // for selecting notes in the tab editor
      display: { scale: zoom / 100 },
      // the saved tracks, else the user's instruments' tracks, or null for AlphaTab's default (the first track)
      tracks: this.note.tracks ?? this.songValue.tracks,
      player: {
        enablePlayer: true,
        soundFont: "/sonivox.sf2",
        // scrolls the page (AlphaTab's default scroll element), so the header scrolls away with the score
        scrollOffsetX: -10,
      },
    })

    this.applyThemeColors()
    this.tabEditor = new TabEditor(this.api, this.canvasTarget.parentElement, {
      locate: note => this.locateNote(note),
      context: trackTab => this.tabContext(trackTab),
      move: (trackTab, index, string) => this.moveNote(trackTab, index, string),
    })

    this.themeObserver = new MutationObserver(() => {
      this.applyThemeColors()
      this.api.updateSettings()
      this.api.render()
    })
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-bs-theme"],
    })

    // the track panel ends above the footer controls, whose height changes with the sync editor
    this.dockObserver = new ResizeObserver(([entry]) => {
      this.element.style.setProperty("--dock-height", `${entry.borderBoxSize[0].blockSize}px`)
    })
    this.dockObserver.observe(this.dockTarget)

    this.restoreVolume()

    this.api.error.on((e) => console.error("alphaTab error", e))
    this.api.renderStarted.on((isResize) => this.handleRenderStarted(isResize))
    this.api.soundFontLoad.on((args) => this.handleSoundFontLoad(args))
    this.api.soundFontLoaded.on(() => this.handleSoundFontLoaded())
    this.api.renderFinished.on(() => this.handleRenderFinished())
    this.api.scoreLoaded.on((score) => this.handleScoreLoaded(score))
    this.api.playerPositionChanged.on((args) => this.handlePlayerPositionChanged(args))
    this.api.playerReady.on(() => this.handlePlayerReady())
    this.api.playerStateChanged.on((args) => this.handlePlayerStateChanged(args))
    this.api.midiLoaded.on(() => this.rangeRestored || this.restoreRange())
    this.api.playbackRangeChanged.on(() => this.scheduleNoteSave())
  }

  disconnect() {
    document.removeEventListener("keydown", this.keyHandler)
    window.removeEventListener('beforeunload', this.unloadHandler)
    clearTimeout(this.historyTimer)
    this.flushHistory()
    this.flushNote()
    this.alternateTabs.flush({ keepalive: true })
    if (this.themeObserver) {
      this.themeObserver.disconnect()
      this.themeObserver = null
    }
    this.dockObserver?.disconnect()
    this.tabEditor?.destroy()
    if (this.api) {
      this.api.destroy()
      this.api = null
    }
  }

  // --- AlphaTab event handlers ---

  handleRenderStarted(isResize) {
    if (!isResize && !this.renderingEdit) {
      this.element.classList.add("loading")
    }
    const tracks = new Map()
    for (const t of this.api.tracks) {
      tracks.set(t.index, t)
    }
    for (const trackItem of this.trackItems) {
      const isActive = tracks.has(trackItem.track.index)
      trackItem.classList.toggle("active", isActive)
      trackItem.querySelector(".at-track-check").checked = isActive
    }
  }

  handleSoundFontLoad(args) {
    this.updateProgress(this.playerLoadingTarget, args.loaded / args.total)
  }

  handleSoundFontLoaded() {
    this.playerLoadingTarget.classList.add("d-none")
  }

  handleRenderFinished() {
    this.renderingEdit = false
    this.element.classList.remove("loading")
  }

  async handleScoreLoaded(score) {
    this.loadTrackTabs(score)
    this.songTitleTarget.innerText = this.songValue.title ?? score.title

    let artist = this.songValue.artist ?? score.artist
    if ( artist ) artist = "&ndash; " + artist
    this.songArtistTarget.innerHTML = artist

    this.trackListTarget.innerHTML = ""
    for (const track of score.tracks) {
      const trackItem = this.createTrackItem(track)
      this.trackItems.push(trackItem)
      this.trackListTarget.appendChild(trackItem)
    }

    this.currentTempo = score.tempo

    if (this.songValue.syncPoints !== null) {
      score.applyFlatSyncPoints(this.songValue.syncPoints)

      const response = await fetch(`/s/${this.songValue.id}/audio`)
      const arrayBuffer = await response.arrayBuffer()
      score.backingTrack = new alphaTab.model.BackingTrack()
      score.backingTrack.rawAudioFile = new Uint8Array(arrayBuffer)

      this.api.settings.player.playerMode = alphaTab.PlayerMode.EnabledBackingTrack
      this.api.updateSettings()

      if (this.hasSyncEditorOutlet) {
        this.syncEditorOutlet.initWithApi(this.api, score)
      }
    }
  }

  toggleSyncEditor(e) {
    e.preventDefault()
    if (this.hasSyncEditorOutlet) {
      this.syncEditorOutlet.toggle()
    }
  }

  handlePlayerPositionChanged(args) {
    const currentSeconds = (args.currentTime / 1000) | 0
    if (currentSeconds === this.previousTime) return
    this.previousTime = currentSeconds

    this.timePositionTarget.innerText = `${this.formatDuration(args.currentTime)} / ${this.formatDuration(args.endTime)}`
    this.timeSliderValueTarget.style.width = `${((args.currentTime / args.endTime) * 100).toFixed(2)}%`
  }

  handlePlayerReady() {
    for (const c of this.element.querySelectorAll(".at-player .disabled")) {
      c.classList.remove("disabled")
    }
    this.restoreRange()
    this.applyNote()
  }

  handlePlayerStateChanged(args) {
    const icon = this.playPauseTarget.querySelector("i")
    if (args.state === 0) {
      // Paused or stopped
      icon.classList.remove("fa-pause")
      icon.classList.add("fa-play")
      if (this.playStartedAt !== null) {
        this.accumulatedSeconds += (Date.now() - this.playStartedAt) / 1000
        this.playStartedAt = null
      }
      this.scheduleHistoryPost()
    } else {
      // Playing
      icon.classList.remove("fa-play")
      icon.classList.add("fa-pause")
      if (this.playStartedAt === null) {
        this.playStartedAt = Date.now()
        if (!this.playDate) {
          // the local date, since toISOString() gives the UTC date, which is tomorrow in the evening in the Americas
          const now = new Date()
          this.playDate = [now.getFullYear(), now.getMonth() + 1, now.getDate()]
            .map(n => String(n).padStart(2, '0')).join('-')
        }
      }
      clearTimeout(this.historyTimer)
    }
  }

  // --- Actions ---

  playPause(e) {
    e.preventDefault() // a '#' link, which would scroll to the top of the page
    e.stopPropagation()
    if (!e.currentTarget.classList.contains("disabled")) {
      this.api.playPause()
    }
  }

  // Stops playback, moving back to the start (of the playback range, if any) and scrolling it into view, or, when already
  // stopped there, goes to the previous song in the playlist
  skipBack(e) {
    e.preventDefault()
    e.stopPropagation()
    if (e.currentTarget.classList.contains("disabled")) return

    // (within a 64th note of AlphaTab's 960-tick quarter note, since with a backing track the stopped position is converted from
    // its time, landing a tick or two off)
    const atStart = this.api.tickPosition - (this.api.playbackRange?.startTick ?? 0) < 960 / 16
    if (this.previousUrlValue && this.api.playerState === alphaTab.synth.PlayerState.Paused && atStart) {
      window.location.href = this.previousUrlValue
      return
    }

    // The cursor moves asynchronously, two animation frames after the player reports its new position (one to find its beat, then
    // one to move it there), which the player does just before reporting it stopped (but after any position it reported while
    // still playing)
    const scroll = ({ stopped }) => {
      if (!stopped) return
      this.api.playerStateChanged.off(scroll)
      requestAnimationFrame(() => requestAnimationFrame(() => this.api.scrollToCursor()))
    }
    this.api.playerStateChanged.on(scroll)
    this.api.stop()
  }

  toggleCountIn(e) {
    e.preventDefault()
    e.stopPropagation()
    this.setCountIn(!this.countInTarget.classList.contains("active"))
    this.scheduleNoteSave()
  }

  toggleMetronome(e) {
    e.preventDefault()
    e.stopPropagation()
    this.setMetronome(!this.metronomeTarget.classList.contains("active"))
    this.scheduleNoteSave()
  }

  toggleLoop(e) {
    e.preventDefault()
    e.stopPropagation()
    this.setLoop(!this.loopTarget.classList.contains("active"))
    this.scheduleNoteSave()
  }

  setCountIn(on) {
    this.countInTarget.classList.toggle("active", on)
    this.api.countInVolume = on ? 1 : 0
  }

  setMetronome(on) {
    this.metronomeTarget.classList.toggle("active", on)
    this.api.metronomeVolume = on ? 1 : 0
  }

  setLoop(on) {
    this.loopTarget.classList.toggle("active", on)
    this.api.isLooping = on
  }

  toggleTracks(e) {
    e.preventDefault()
    this.trackPanelTarget.classList.toggle("open")
  }

  changeSpeed(e) {
    e.preventDefault()
    this.setSpeed(Number.parseInt(e.target.value) / 100)
    this.scheduleNoteSave()
  }

  setSpeed(speed) {
    this.api.playbackSpeed = speed
    this.speedSliderTarget.value = Math.round(speed * 100)
    this.speedLabelTarget.innerText = `${speed}x`
  }

  changeVolume(e) {
    e.preventDefault()
    const volume = Number.parseInt(e.target.value)
    this.api.masterVolume = volume / 100
    this.updateVolumeUI(volume)
    localStorage.setItem('playerVolume', volume)
    this.scheduleNoteSave()
  }

  changeZoom(e) {
    e.preventDefault()
    const value = Number.parseInt(e.target.value)
    this.zoomLabelTarget.innerText = `${value}%`
    localStorage.setItem('playerScale', value)
    clearTimeout(this.zoomDebounce)
    this.zoomDebounce = setTimeout(() => {
      this.api.settings.display.scale = value / 100.0
      this.api.updateSettings()
      this.api.render()
    }, 150)
  }

  changeLayout(e) {
    e.preventDefault()
    const settings = this.api.settings
    switch (e.target.dataset.layout) {
      case "page":
        settings.display.layoutMode = alphaTab.LayoutMode.Page
        settings.player.scrollMode = alphaTab.ScrollMode.Continuous
        break
      case "horizontal-bar":
        settings.display.layoutMode = alphaTab.LayoutMode.Horizontal
        settings.player.scrollMode = alphaTab.ScrollMode.Continuous
        break
      case "horizontal-screen":
        settings.display.layoutMode = alphaTab.LayoutMode.Horizontal
        settings.player.scrollMode = alphaTab.ScrollMode.OffScreen
        break
    }
    this.api.updateSettings()
    this.api.render()
  }

  handleKeydown(e) {
    if (e.defaultPrevented || e.target.matches('input, textarea, select')) return
    if (this.tabEditor.handleKey(e)) {
      e.preventDefault()
      return
    }

    switch (e.code) {
      case "NumpadAdd":
        this.stepSpeed(1)
        e.preventDefault()
        return
      case "NumpadSubtract":
        this.stepSpeed(-1)
        e.preventDefault()
        return
    }

    switch (e.key) {
      case "ArrowUp":
        this.stepVolume(1)
        e.preventDefault()
        break
      case "ArrowDown":
        this.stepVolume(-1)
        e.preventDefault()
        break
      case "ArrowLeft":
        this.skipBars(-1)
        e.preventDefault()
        break
      case "ArrowRight":
        this.skipBars(1)
        e.preventDefault()
        break
      case " ":
        this.playPauseTarget.click()
        e.preventDefault()
        break
    }
  }

  // Changes the volume by the given number of 5% steps
  stepVolume(steps) {
    const volume = Math.min(Math.max(Math.round(this.api.masterVolume * 100) + steps * 5, 0), 100)
    this.api.masterVolume = volume / 100
    this.syncVolumeUI()
    this.scheduleNoteSave()
    this.showOsd(this.volumeIconTarget.className, `${volume}%`)
  }

  // Changes the speed by the given number of the speed slider's steps, within its range
  stepSpeed(steps) {
    const slider = this.speedSliderTarget
    const percent = Number.parseInt(slider.value) + steps * Number.parseInt(slider.step)
    const clamped = Math.min(Math.max(percent, Number.parseInt(slider.min)), Number.parseInt(slider.max))
    this.setSpeed(clamped / 100)
    this.scheduleNoteSave()
    this.showOsd("fas fa-gauge", `${clamped / 100}x`)
  }

  // Moves the playback position to the start of the bar the given number of bars from the current one, in playback order
  // (with repeats expanded)
  skipBars(count) {
    const bars = this.api.tickCache?.masterBars
    if (!bars?.length) return
    const tick = this.api.tickPosition
    const current = bars.findIndex(bar => tick >= bar.start && tick < bar.end)
    const index = current < 0 ? (count < 0 ? bars.length : -1) : current
    this.api.tickPosition = bars[Math.min(Math.max(index + count, 0), bars.length - 1)].start
  }

  // Briefly shows an on-screen display of a new setting's icon and value
  showOsd(iconClass, text) {
    this.osdIconTarget.className = iconClass
    this.osdTextTarget.innerText = text
    this.osdTarget.classList.add("visible")
    clearTimeout(this.osdTimeout)
    this.osdTimeout = setTimeout(() => this.osdTarget.classList.remove("visible"), 800)
  }

  // --- Theme ---

  applyThemeColors() {
    const dark = document.documentElement.getAttribute("data-bs-theme") === "dark"
    const res = this.api.settings.display.resources

    if (dark) {
      res.mainGlyphColor = new alphaTab.model.Color(222, 226, 230)
      res.secondaryGlyphColor = new alphaTab.model.Color(222, 226, 230, 102)
      res.scoreInfoColor = new alphaTab.model.Color(222, 226, 230)
      res.barSeparatorColor = new alphaTab.model.Color(173, 181, 189)
      res.barNumberColor = new alphaTab.model.Color(234, 108, 108)
      res.staffLineColor = new alphaTab.model.Color(108, 117, 125)
    } else {
      res.mainGlyphColor = new alphaTab.model.Color(0, 0, 0)
      res.secondaryGlyphColor = new alphaTab.model.Color(0, 0, 0, 102)
      res.scoreInfoColor = new alphaTab.model.Color(0, 0, 0)
      res.barSeparatorColor = new alphaTab.model.Color(34, 34, 17)
      res.barNumberColor = new alphaTab.model.Color(200, 0, 0)
      res.staffLineColor = new alphaTab.model.Color(165, 165, 165)
    }
  }

  // --- Volume helpers ---

  // Restores the song's saved volume, or else the last volume used for any song
  restoreVolume() {
    const stored = localStorage.getItem('playerVolume')
    const volume = this.note.volume ?? (stored !== null ? Number.parseInt(stored) : 50)
    this.api.masterVolume = volume / 100
    this.volumeSliderTarget.value = volume
    this.updateVolumeUI(volume)
  }

  syncVolumeUI() {
    const volume = Math.round(this.api.masterVolume * 100)
    this.volumeSliderTarget.value = volume
    this.updateVolumeUI(volume)
    localStorage.setItem('playerVolume', volume)
    this.scheduleNoteSave()
  }

  updateVolumeUI(volume) {
    this.volumeLabelTarget.innerText = `${volume}%`
    const icon = this.volumeIconTarget
    icon.classList.remove('fa-volume-high', 'fa-volume-low', 'fa-volume-off')
    if (volume > 50) {
      icon.classList.add('fa-volume-high')
    } else if (volume > 0) {
      icon.classList.add('fa-volume-low')
    } else {
      icon.classList.add('fa-volume-off')
    }
  }

  // --- Zoom helpers ---

  // Shows the last score scale used for any song on the slider, and returns it (as a percentage)
  restoreZoom() {
    const stored = localStorage.getItem('playerScale')
    const zoom = stored !== null ? Number.parseInt(stored) : 100
    this.zoomSliderTarget.value = zoom
    this.zoomLabelTarget.innerText = `${zoom}%`
    return zoom
  }

  // --- Song note (the user's player settings for this song) ---

  // Applies the saved speed and toggles, and the track panel's mixer settings (restored from the note in createTrackItem), once
  // the player is ready
  applyNote() {
    const note = this.note
    if (note.speed) this.setSpeed(note.speed)
    this.setCountIn(!!note.count_in)
    this.setMetronome(!!note.metronome)
    this.setLoop(!!note.looping)
    for (const trackItem of this.trackItems) {
      const { track } = trackItem
      const mix = this.trackMix(trackItem)
      this.api.changeTrackMute([track], mix.mute)
      this.api.changeTrackSolo([track], mix.solo)
      this.setTrackVolume(track, mix.volume)
    }
    this.savedNote = JSON.stringify(this.currentNote())
  }

  // Selects the saved playback range, highlighting the beats of the first shown track at its ends, and moves the playback
  // position to its start.  This needs the MIDI (for the tick lookup), and is repeated whenever a player is created, since a
  // new player (e.g. when the backing track is set up after loading, see handleScoreLoaded) starts without a range, at the
  // beginning.
  restoreRange() {
    const tickCache = this.api.tickCache
    const { range_start_tick: startTick, range_end_tick: endTick } = this.note
    if (!tickCache || startTick == null || endTick == null) return
    this.rangeRestored = true

    const beats = this.api.tracks[0]?.staves[0]?.bars.flatMap(bar => bar.voices[0]?.beats ?? []) ?? []
    const startBeat = beats.findLast(beat => tickCache.getBeatStart(beat) <= startTick)
    const endBeat = beats.findLast(beat => tickCache.getBeatStart(beat) < endTick)
    if (startBeat && endBeat) this.api.highlightPlaybackRange(startBeat, endBeat)

    this.api.playbackRange = Object.assign(new alphaTab.synth.PlaybackRange(), { startTick, endTick })
    this.api.tickPosition = startTick
    if (this.savedNote !== null) this.savedNote = JSON.stringify(this.currentNote())
  }

  currentNote() {
    const range = this.api.playbackRange
    const tracks = this.api.tracks.map(track => track.index)
    const defaultTracks = this.songValue.tracks ?? [0]
    const isDefault = tracks.length === defaultTracks.length && tracks.every((index, i) => index === defaultTracks[i])
    const mixes = this.trackItems.map(trackItem => ({ index: trackItem.track.index, ...this.trackMix(trackItem) }))
    return {
      speed: this.api.playbackSpeed,
      volume: Math.round(this.api.masterVolume * 100),
      looping: this.api.isLooping,
      count_in: this.api.countInVolume > 0,
      metronome: this.api.metronomeVolume > 0,
      range_start_tick: range?.startTick ?? null,
      range_end_tick: range?.endTick ?? null,
      tracks: isDefault ? null : tracks,  // null follows the user's instruments if they change
      muted_tracks: mixes.filter(mix => mix.mute).map(mix => mix.index),
      solo_tracks: mixes.filter(mix => mix.solo).map(mix => mix.index),
      track_volumes: Object.fromEntries(mixes.map(mix => [mix.index, mix.volume])),
      track_tunings: Object.keys(this.trackTunings).length > 0 ? this.trackTunings : null,
    }
  }

  scheduleNoteSave() {
    clearTimeout(this.noteTimer)
    this.noteTimer = setTimeout(() => this.saveNote(), 1000)
  }

  flushNote() {
    clearTimeout(this.noteTimer)
    this.saveNote()
  }

  // Saves the note if it changed (keepalive lets it finish while the page unloads)
  saveNote() {
    if (this.savedNote === null || !this.api) return
    const note = JSON.stringify(this.currentNote())
    if (note === this.savedNote) return

    const previous = this.savedNote
    this.savedNote = note
    this.note = JSON.parse(note)
    fetch(`/s/${this.songValue.id}/note`, {
      method: 'PATCH',
      keepalive: true,
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content,
      },
      body: JSON.stringify({ song_note: JSON.parse(note) }),
    }).then(response => {
      if (!response.ok) throw new Error(`Note PATCH failed: ${response.status}`)
    }).catch(e => {
      if (this.savedNote === note) this.savedNote = previous  // so the next change retries
      console.error('Failed to save song note', e)
    })
  }

  // --- Alternate tabs (the user's own fingerings of the stringed tracks, see AlternateTab) ---

  // Indexes the stringed tracks' notes (dropping tabs that don't fit them), and fingers them in the user's chosen tunings
  loadTrackTabs(score) {
    this.trackTabs = new Map(score.tracks.filter(TrackTab.isStringed).map(track => [track.index, new TrackTab(track)]))
    for (const tab of [...this.alternateTabs.tabs]) {
      if (tab.noteCount === this.trackTabs.get(tab.trackIndex)?.notes.length) continue
      console.warn(`Ignoring alternate tab ${tab.id}, for another version of the score`)
      this.alternateTabs.forget(tab)  // a new tab for its tuning replaces it
    }
    for (const index of this.trackTabs.keys()) {
      if (!this.applyTuning(index, this.trackTunings[index] ?? null)) delete this.trackTunings[index]
    }
  }

  // The user's tab for a track in a tuning (null for the score's), if any
  alternateTab(index, tuning) {
    return this.alternateTabs.find(index, tuning ?? this.trackTabs.get(index).originalTuning) ?? null
  }

  // Fingers a track in a tuning (null for the score's) with the user's tab, returning false (fingering it in the score's
  // tuning) if there's none for the tuning
  applyTuning(index, tuning) {
    const trackTab = this.trackTabs.get(index)
    const tab = this.alternateTab(index, tuning)
    if (tuning && !tab) {
      trackTab.apply(null, this.alternateTab(index, null)?.strings)
      return false
    }
    trackTab.apply(tuning, tab?.strings)
    return true
  }

  // Fills a stringed track's tuning pulldown: "Original" and the presets it can be played in, marking those with a tab
  setupTuningRow(trackItem, trackTab) {
    const select = trackItem.querySelector(".at-track-tuning")
    select.add(new Option(`Original (${noteNames(trackTab.originalTuning)})`, ''))
    for (const group of tuningGroups(trackTab, this.songValue.trackTypes?.[trackTab.track.index])) {
      const optgroup = document.createElement('optgroup')
      optgroup.label = group.label
      for (const { tuning, label } of group.tunings) {
        const option = new Option(label, JSON.stringify(tuning))
        option.dataset.label = label
        optgroup.append(option)
      }
      select.add(optgroup)
    }
    select.onchange = () => this.changeTuning(trackItem, select.value ? JSON.parse(select.value) : null)
    trackItem.querySelector(".at-track-tuning-reset").onclick = () => this.resetTuning(trackItem)
    this.updateTuningRow(trackTab.track.index, trackItem)
  }

  // Shows a track's chosen tuning, marks the tunings it has tabs for, and enables Reset if there's a tab to reset
  updateTuningRow(index, trackItem = this.trackItem(index)) {
    const tuning = this.trackTunings[index] ?? null
    const select = trackItem.querySelector(".at-track-tuning")
    select.value = tuning ? JSON.stringify(tuning) : ''
    for (const option of select.querySelectorAll("option[data-label]")) {
      option.text = `${this.alternateTab(index, JSON.parse(option.value)) ? "• " : ""}${option.dataset.label}`
    }
    trackItem.querySelector(".at-track-tuning-reset").disabled = !this.alternateTab(index, tuning)
  }

  trackItem(index) {
    return this.trackItems.find(item => item.track.index === index)
  }

  // Fingers a track in a tuning (null for the score's), generating its tab if there's none yet
  async changeTuning(trackItem, tuning) {
    const { index } = trackItem.track
    this.showTuningMessage(index, null)
    if (tuning && !this.alternateTab(index, tuning)) {
      const strings = await this.optimize(trackItem, tuning)
      if (!strings) {
        this.updateTuningRow(index)
        const name = alphaTab.model.Tuning.findTuning(tuning)?.name ?? noteNames(tuning)
        this.showTuningMessage(index, `This track can't be played in ${name}`)
        return
      }
      this.alternateTabs.add(index, tuning, this.trackTabs.get(index).notes.length, strings, DEFAULT_OPTIMIZER)
    }

    if (tuning) this.trackTunings[index] = tuning
    else delete this.trackTunings[index]
    this.applyTuning(index, tuning)
    this.updateTuningRow(index)
    this.renderEdit()
    this.scheduleNoteSave()
  }

  // Discards the user's changes to a track's tab in its tuning: the score's fingering for its own tuning, else a new fingering
  async resetTuning(trackItem) {
    const { index } = trackItem.track
    const tuning = this.trackTunings[index] ?? null
    const tab = this.alternateTab(index, tuning)
    if (!tab || !confirm("Discard your changes to this track's tab?")) return

    if (tuning) {
      const strings = await this.optimize(trackItem, tuning)
      if (!strings) return
      this.alternateTabs.replace(tab, strings, DEFAULT_OPTIMIZER)
    } else {
      this.alternateTabs.remove(tab)
    }
    this.applyTuning(index, tuning)
    this.updateTuningRow(index)
    this.renderEdit()
  }

  // The default optimizer's fingering of a track in a tuning, as a tab's strings (see TrackTab#stringsFor), or null if the track
  // can't be played in it; the pulldown is disabled with a spinner meanwhile
  async optimize(trackItem, tuning) {
    const trackTab = this.trackTabs.get(trackItem.track.index)
    const select = trackItem.querySelector(".at-track-tuning")
    select.disabled = true
    trackItem.classList.add("optimizing")
    try {
      await new Promise(resolve => requestAnimationFrame(() => setTimeout(resolve)))  // shows the spinner before optimizing
      const fingering = await optimizers[DEFAULT_OPTIMIZER](trackTab.problem(tuning))
      return fingering && trackTab.stringsFor(fingering)
    } finally {
      select.disabled = false
      trackItem.classList.remove("optimizing")
    }
  }

  // Turns the tab editor on or off (with the footer button)
  toggleTabEditing(e) {
    e?.preventDefault()
    const on = !this.tabEditTarget.classList.contains("active")
    this.tabEditTarget.classList.toggle("active", on)
    this.element.classList.toggle("editing-tab", on)
    this.tabEditor.setActive(on)
    if (!on) this.alternateTabs.flush()
  }

  // The stringed track and index of an AlphaTab note, if it's on a stringed staff
  locateNote(note) {
    for (const trackTab of this.trackTabs.values()) {
      const index = trackTab.indexes.get(note)
      if (index !== undefined) return { trackTab, index }
    }
    return null
  }

  // A track's current tuning and strings, for moving its notes
  tabContext(trackTab) {
    const { index } = trackTab.track
    const tuning = this.trackTunings[index] ?? null
    return { tuning: tuning ?? trackTab.originalTuning, strings: this.alternateTab(index, tuning)?.strings ?? {} }
  }

  // Moves a note and the notes chained to it to a string, in the track's tab for its tuning (creating the score tuning's tab)
  moveNote(trackTab, i, string) {
    const { index } = trackTab.track
    const tuning = this.trackTunings[index] ?? null
    const changes = trackTab.moveChanges(i, string)
    const tab = this.alternateTab(index, tuning)
    if (tab) {
      this.alternateTabs.edit(tab, changes)
    } else {
      const strings = Object.fromEntries(Object.entries(changes).filter(([, change]) => change !== null))
      this.alternateTabs.add(index, trackTab.originalTuning, trackTab.notes.length, strings)
    }
    this.applyTuning(index, tuning)
    this.updateTuningRow(index)
    this.renderEdit()
  }

  // Re-renders the score after changing its fingering, in place and without the loading overlay
  renderEdit() {
    this.renderingEdit = true
    this.api.render({ reuseViewport: true })
  }

  // Shows a message under a track's tuning pulldown, or hides it (for null)
  showTuningMessage(index, message) {
    const element = this.trackItem(index)?.querySelector(".at-track-tuning-message")
    if (!element) return
    element.textContent = message ?? ""
    element.classList.toggle("d-none", !message)
  }

  // --- Helpers ---

  scheduleHistoryPost() {
    clearTimeout(this.historyTimer)
    this.historyTimer = setTimeout(() => this.postHistory(), 2000)
  }

  async postHistory() {
    if (this.accumulatedSeconds <= 0 || !this.playDate) return
    const duration = this.accumulatedSeconds
    this.accumulatedSeconds = 0
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch(`/s/${this.songValue.id}/track`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-CSRF-Token': csrfToken,
        },
        body: new URLSearchParams({
          date: this.playDate,
          duration: duration.toString(),
        }),
      })
      if (!response.ok) throw new Error(`Track POST failed: ${response.status}`)
      this.playDate = null
    } catch (e) {
      this.accumulatedSeconds += duration  // restore on failure
      console.error('Failed to post play history', e)
    }
  }

  flushHistory() {
    clearTimeout(this.historyTimer)
    if (this.playStartedAt !== null) {
      this.accumulatedSeconds += (Date.now() - this.playStartedAt) / 1000
      this.playStartedAt = null
    }
    if (this.accumulatedSeconds <= 0 || !this.playDate) return
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const data = new URLSearchParams({
      authenticity_token: csrfToken ?? '',
      date: this.playDate,
      duration: this.accumulatedSeconds.toString(),
    })
    navigator.sendBeacon(`/s/${this.songValue.id}/track`, data)
    this.accumulatedSeconds = 0
    this.playDate = null
  }

  createTrackItem(track) {
    const template = this.trackTemplateTarget
    const clone = template.content.cloneNode(true)
    const trackItem = clone.firstElementChild

    trackItem.querySelector(".at-track-name").textContent = track.name
    trackItem.querySelector(".at-track-type").textContent = this.songValue.trackTypes?.[track.index] ?? ""

    const checkbox = trackItem.querySelector(".at-track-check")
    const muteButton = trackItem.querySelector(".at-track-mute")
    const soloButton = trackItem.querySelector(".at-track-solo")
    const volumeSlider = trackItem.querySelector(".at-track-volume")

    checkbox.onchange = () => {
      const selected = this.trackItems
        .filter(item => item.querySelector(".at-track-check").checked)
        .map(item => item.track)
      if (selected.length > 0) {
        this.api.renderTracks(selected)
        this.scheduleNoteSave()
      } else {
        checkbox.checked = true
      }
    }

    muteButton.onclick = () => {
      this.api.changeTrackMute([track], muteButton.classList.toggle("active"))
      this.scheduleNoteSave()
    }

    soloButton.onclick = () => {
      this.api.changeTrackSolo([track], soloButton.classList.toggle("active"))
      this.scheduleNoteSave()
    }

    volumeSlider.oninput = () => {
      this.setTrackVolume(track, Number.parseInt(volumeSlider.value))
      this.scheduleNoteSave()
    }

    // the saved mixer settings, else the score's
    const { muted_tracks: muted, solo_tracks: solo, track_volumes: volumes } = this.note
    muteButton.classList.toggle("active", muted?.includes(track.index) ?? track.playbackInfo.isMute)
    soloButton.classList.toggle("active", solo?.includes(track.index) ?? track.playbackInfo.isSolo)
    volumeSlider.value = volumes?.[track.index] ?? track.playbackInfo.volume

    trackItem.track = track
    const trackTab = this.trackTabs.get(track.index)
    if (trackTab) this.setupTuningRow(trackItem, trackTab)
    else trackItem.querySelector(".at-track-tuning-row").remove()
    return trackItem
  }

  // The track's mixer settings in the track panel
  trackMix(trackItem) {
    return {
      mute: trackItem.querySelector(".at-track-mute").classList.contains("active"),
      solo: trackItem.querySelector(".at-track-solo").classList.contains("active"),
      volume: Number.parseInt(trackItem.querySelector(".at-track-volume").value),
    }
  }

  // Sets the track's volume (0-16, like the score's), which the player takes as a factor of the score's volume
  setTrackVolume(track, volume) {
    this.api.changeTrackVolume([track], volume / Math.max(track.playbackInfo.volume, 1))
  }

  formatDuration(milliseconds) {
    let seconds = milliseconds / 1000
    const minutes = (seconds / 60) | 0
    seconds = (seconds - minutes * 60) | 0
    return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
  }

  updateProgress(el, value) {
    const percentValue = value * 100
    const left = el.querySelector(".progress-left .progress-bar")
    const right = el.querySelector(".progress-right .progress-bar")
    function percentageToDegrees(percentage) {
      return (percentage / 100) * 360
    }

    if (percentValue > 0) {
      if (percentValue <= 50) {
        right.style.transform = `rotate(${percentageToDegrees(percentValue)}deg)`
      } else {
        right.style.transform = "rotate(180deg)"
        left.style.transform = `rotate(${percentageToDegrees(percentValue - 50)}deg)`
      }
    }
    el.querySelector(".progress-value-number").innerText = percentValue | 0
  }
}
