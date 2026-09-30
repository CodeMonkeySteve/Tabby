import { Controller } from "@hotwired/stimulus"
import * as alphaTab from "@coderline/alphatab"

export default class extends Controller {
  static values = {
    song: Object,
  }

  static outlets = ["sync-editor"]

  static targets = [
    "canvas", "dock", "trackList", "trackPanel", "playerLoading",
    "songTitle", "songArtist", "timePosition", "timeSliderValue",
    "playPause", "stop", "countIn", "metronome", "loop",
    "speedLabel", "speedSlider", "zoomLabel", "zoomSlider", "trackTemplate",
    "volumeLabel", "volumeSlider", "volumeIcon",
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
    this.savedNote = null          // JSON of the last saved (or restored) note, null until the saved note is applied
    this.noteTimer = null          // debounce timer handle
    this.rangeRestored = false
    this.unloadHandler = () => {
      this.flushHistory()
      this.flushNote()
    }
    window.addEventListener('beforeunload', this.unloadHandler)

    this.keyHandler = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.keyHandler)

    this.api = new alphaTab.AlphaTabApi(this.canvasTarget, {
      file: `/s/${this.songValue.id}/score`,
      tracks: this.songValue.tracks, // the user's instruments' tracks, or null for AlphaTab's default (the first track)
      player: {
        enablePlayer: true,
        soundFont: "/sonivox.sf2",
        // scrolls the page (AlphaTab's default scroll element), so the header scrolls away with the score
        scrollOffsetX: -10,
      },
    })

    this.applyThemeColors()

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
    if (this.themeObserver) {
      this.themeObserver.disconnect()
      this.themeObserver = null
    }
    this.dockObserver?.disconnect()
    if (this.api) {
      this.api.destroy()
      this.api = null
    }
  }

  // --- AlphaTab event handlers ---

  handleRenderStarted(isResize) {
    if (!isResize) {
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
    this.element.classList.remove("loading")
  }

  async handleScoreLoaded(score) {
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
          this.playDate = new Date().toISOString().slice(0, 10)
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

  stopPlayback(e) {
    e.preventDefault()
    e.stopPropagation()
    if (!e.currentTarget.classList.contains("disabled")) {
      this.api.stop()
    }
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
  }

  changeZoom(e) {
    e.preventDefault()
    const value = Number.parseInt(e.target.value)
    this.zoomLabelTarget.innerText = `${value}%`
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

    switch (e.key) {
      case "ArrowUp":
        this.api.masterVolume = Math.min(this.api.masterVolume + 0.05, 1.0)
        this.syncVolumeUI()
        e.preventDefault()
        break
      case "ArrowDown":
        this.api.masterVolume = Math.max(this.api.masterVolume - 0.05, 0.0)
        this.syncVolumeUI()
        e.preventDefault()
        break
      case " ":
        this.playPauseTarget.click()
        e.preventDefault()
        break
    }
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

  restoreVolume() {
    const stored = localStorage.getItem('playerVolume')
    const volume = stored !== null ? Number.parseInt(stored) : 50
    this.api.masterVolume = volume / 100
    this.volumeSliderTarget.value = volume
    this.updateVolumeUI(volume)
  }

  syncVolumeUI() {
    const volume = Math.round(this.api.masterVolume * 100)
    this.volumeSliderTarget.value = volume
    this.updateVolumeUI(volume)
    localStorage.setItem('playerVolume', volume)
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

  // --- Song note (the user's player settings for this song) ---

  // Applies the saved speed and toggles once the player is ready
  applyNote() {
    const note = this.note
    if (note.speed) this.setSpeed(note.speed)
    this.setCountIn(!!note.count_in)
    this.setMetronome(!!note.metronome)
    this.setLoop(!!note.looping)
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
    return {
      speed: this.api.playbackSpeed,
      looping: this.api.isLooping,
      count_in: this.api.countInVolume > 0,
      metronome: this.api.metronomeVolume > 0,
      range_start_tick: range?.startTick ?? null,
      range_end_tick: range?.endTick ?? null,
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
      } else {
        checkbox.checked = true
      }
    }

    muteButton.onclick = () => {
      muteButton.classList.toggle("active")
      this.api.changeTrackMute([track], muteButton.classList.contains("active"))
    }

    soloButton.onclick = () => {
      soloButton.classList.toggle("active")
      this.api.changeTrackSolo([track], soloButton.classList.contains("active"))
    }

    volumeSlider.oninput = () => {
      this.api.changeTrackVolume([track], volumeSlider.value / track.playbackInfo.volume)
    }

    muteButton.value = track.playbackInfo.isMute
    soloButton.value = track.playbackInfo.isSolo
    volumeSlider.value = track.playbackInfo.volume

    trackItem.track = track
    return trackItem
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
