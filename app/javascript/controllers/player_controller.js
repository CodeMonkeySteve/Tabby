import { Controller } from "@hotwired/stimulus"
import * as alphaTab from "https://cdn.jsdelivr.net/npm/@coderline/alphatab@alpha/dist/alphaTab.min.mjs"

export default class extends Controller {
  static values = {
    song: Object,
  }

  static outlets = ["sync-editor"]

  static targets = [
    "canvas", "viewport", "trackList", "trackPanel", "playerLoading",
    "songTitle", "songArtist", "timePosition", "timeSliderValue",
    "playPause", "stop", "countIn", "metronome", "loop",
    "speedLabel", "speedSlider", "zoomLabel", "zoomSlider", "trackTemplate",
    "volumeLabel", "volumeSlider", "volumeIcon",
  ]

  connect() {
    this.trackItems = []
    this.currentTempo = 0
    this.previousTime = -1

    this.keyHandler = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.keyHandler)

    this.api = new alphaTab.AlphaTabApi(this.canvasTarget, {
      file: `/s/${this.songValue.id}/score`,
      player: {
        enablePlayer: true,
        soundFont: "/sonivox.sf2",
        scrollElement: this.viewportTarget,
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
  }

  disconnect() {
    document.removeEventListener("keydown", this.keyHandler)
    if (this.themeObserver) {
      this.themeObserver.disconnect()
      this.themeObserver = null
    }
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

  toggleSyncEditor() {
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
  }

  handlePlayerStateChanged(args) {
    const icon = this.playPauseTarget.querySelector("i")
    if (args.state === 0) {
      icon.classList.remove("fa-pause")
      icon.classList.add("fa-play")
    } else {
      icon.classList.remove("fa-play")
      icon.classList.add("fa-pause")
    }
  }

  // --- Actions ---

  playPause(e) {
    e.stopPropagation()
    if (!e.target.classList.contains("disabled")) {
      this.api.playPause()
    }
  }

  stopPlayback(e) {
    e.stopPropagation()
    if (!e.target.classList.contains("disabled")) {
      this.api.stop()
    }
  }

  toggleCountIn(e) {
    e.stopPropagation()
    const link = e.target.closest("a")
    link.classList.toggle("active")
    this.api.countInVolume = link.classList.contains("active") ? 1 : 0
  }

  toggleMetronome(e) {
    e.stopPropagation()
    const link = e.target.closest("a")
    link.classList.toggle("active")
    this.api.metronomeVolume = link.classList.contains("active") ? 1 : 0
  }

  toggleLoop(e) {
    e.stopPropagation()
    const link = e.target.closest("a")
    link.classList.toggle("active")
    this.api.isLooping = link.classList.contains("active")
  }

  toggleTracks(e) {
    e.preventDefault()
    this.trackPanelTarget.classList.toggle("open")
  }

  changeSpeed(e) {
    e.preventDefault()
    const value = Number.parseInt(e.target.value)
    this.api.playbackSpeed = value / 100
    this.speedLabelTarget.innerText = `${value / 100}x`
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

  // --- Helpers ---

  createTrackItem(track) {
    const template = this.trackTemplateTarget
    const clone = template.content.cloneNode(true)
    const trackItem = clone.firstElementChild

    trackItem.querySelector(".at-track-name").textContent = track.name

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
