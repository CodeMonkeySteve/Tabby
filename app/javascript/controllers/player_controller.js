import { Controller } from "@hotwired/stimulus"
import * as alphaTab from "https://cdn.jsdelivr.net/npm/@coderline/alphatab@alpha/dist/alphaTab.min.mjs"

export default class extends Controller {
  static values = {
    songId: String,
    syncPoints: Array,
  }

  static targets = [
    "canvas", "viewport", "trackList", "playerLoading",
    "songTitle", "songArtist", "timePosition", "timeSliderValue",
    "playPause", "stop", "countIn", "metronome", "loop",
    "speedLabel", "zoomLabel", "trackTemplate",
  ]

  connect() {
    this.trackItems = []
    this.currentTempo = 0
    this.previousTime = -1

    this.keyHandler = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.keyHandler)

    this.api = new alphaTab.AlphaTabApi(this.canvasTarget, {
      file: `/s/${this.songIdValue}/score`,
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
      if (tracks.has(trackItem.track.index)) {
        trackItem.classList.add("active")
      } else {
        trackItem.classList.remove("active")
      }
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
    this.songTitleTarget.innerText = score.title
    this.songArtistTarget.innerText = score.artist

    this.trackListTarget.innerHTML = ""
    for (const track of score.tracks) {
      const trackItem = this.createTrackItem(track)
      this.trackItems.push(trackItem)
      this.trackListTarget.appendChild(trackItem)
    }

    this.currentTempo = score.tempo

    if (this.syncPointsValue !== null) {
      score.applyFlatSyncPoints(this.syncPointsValue)

      const response = await fetch(`/s/${this.songIdValue}/audio`)
      const arrayBuffer = await response.arrayBuffer()
      score.backingTrack = new alphaTab.model.BackingTrack()
      score.backingTrack.rawAudioFile = new Uint8Array(arrayBuffer)

      this.api.settings.player.playerMode = alphaTab.PlayerMode.EnabledBackingTrack
      this.api.updateSettings()
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

  printScore() {
    this.api.print()
  }

  downloadScore() {
    const exporter = new alphaTab.exporter.Gp7Exporter()
    const data = exporter.export(this.api.score, this.api.settings)
    const a = document.createElement("a")
    a.download = this.api.score.title.length > 0 ? `${this.api.score.title}.gp` : "song.gp"
    a.href = URL.createObjectURL(new Blob([data]))
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
  }

  changeSpeed(e) {
    e.preventDefault()
    this.api.playbackSpeed = Number.parseFloat(e.target.innerText)
    this.speedLabelTarget.innerText = e.target.innerText
  }

  changeZoom(e) {
    e.preventDefault()
    this.api.settings.display.scale = Number.parseInt(e.target.innerText) / 100.0
    this.zoomLabelTarget.innerText = e.target.innerText
    this.api.updateSettings()
    this.api.render()
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
        e.preventDefault()
        break
      case "ArrowDown":
        this.api.masterVolume = Math.max(this.api.masterVolume - 0.05, 0.0)
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

  // --- Helpers ---

  createTrackItem(track) {
    const template = this.trackTemplateTarget
    const clone = template.content.cloneNode(true)
    const trackItem = clone.firstElementChild

    trackItem.querySelector(".at-track-name").textContent = track.name

    const muteButton = trackItem.querySelector(".at-track-mute")
    const soloButton = trackItem.querySelector(".at-track-solo")
    const volumeSlider = trackItem.querySelector(".at-track-volume")

    muteButton.onclick = (e) => {
      e.stopPropagation()
      muteButton.classList.toggle("active")
      this.api.changeTrackMute([track], muteButton.classList.contains("active"))
    }

    soloButton.onclick = (e) => {
      e.stopPropagation()
      soloButton.classList.toggle("active")
      this.api.changeTrackSolo([track], soloButton.classList.contains("active"))
    }

    volumeSlider.oninput = (e) => {
      e.preventDefault()
      this.api.changeTrackVolume([track], volumeSlider.value / track.playbackInfo.volume)
    }

    volumeSlider.onclick = (e) => {
      e.stopPropagation()
    }

    trackItem.onclick = (e) => {
      e.stopPropagation()
      this.api.renderTracks([track])
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
