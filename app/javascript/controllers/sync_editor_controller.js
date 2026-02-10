import { Controller } from '@hotwired/stimulus'
import {
  MarkerType,
  markerTypeName,
  buildSyncPointInfoFromAudio,
  autoSync,
  resetSyncPoints,
  applySyncPoints,
  toFlatSyncPoints,
  moveMarker,
  toggleMarker,
  drawWaveform,
  computeMaxAmplitude,
  buildMarkerLabel,
  timePositionToX,
  xToTimePosition,
  createUndoStack,
  storeUndo,
  undo,
  redo,
  canUndo,
  canRedo,
} from 'lib/sync_point_info'

const pixelPerMs = 0.1
const leftPadding = 20
const dragLimit = 10
const dragThreshold = 5

export default class extends Controller {
  static values = { songId: String }
  static targets = [
    'container', 'canvas', 'syncArea', 'markerWrap', 'cursor',
    'zoomLabel', 'undoBtn', 'redoBtn', 'saveBtn', 'statusMsg',
  ]

  connect() {
    this.api = null
    this.score = null
    this.syncPointInfo = null
    this.zoom = 1
    this.undoStack = createUndoStack()
    this.maxAmplitude = 1
    this.draggingMarker = null
    this.dragInfo = null
    this.playbackTime = 0

    this.boundMouseMove = this.onDocumentMouseMove.bind(this)
    this.boundMouseUp = this.onDocumentMouseUp.bind(this)

    this.resizeObserver = new ResizeObserver(() => this.redraw())
    if (this.hasSyncAreaTarget) {
      this.resizeObserver.observe(this.syncAreaTarget)
    }
  }

  disconnect() {
    document.removeEventListener('mousemove', this.boundMouseMove)
    document.removeEventListener('mouseup', this.boundMouseUp)
    this.resizeObserver.disconnect()
    if (this.animFrameId) cancelAnimationFrame(this.animFrameId)
  }

  // Called by the player controller after backing track loads
  async initWithApi(api, score) {
    this.api = api
    this.score = score
    this.syncPointInfo = await buildSyncPointInfoFromAudio(api)

    if (this.syncPointInfo) {
      this.maxAmplitude = computeMaxAmplitude(
        this.syncPointInfo.leftSamples,
        this.syncPointInfo.rightSamples,
      )
      storeUndo(this.undoStack, this.syncPointInfo)
      applySyncPoints(this.api, this.syncPointInfo)
      this.renderAll()
    }
  }

  // --- Toggle visibility ---

  toggle() {
    this.element.classList.toggle('open')
    if (this.element.classList.contains('open') && this.syncPointInfo) {
      this.renderAll()
      this.startPlaybackTracking()
    } else {
      this.stopPlaybackTracking()
    }
  }

  // --- Toolbar actions ---

  zoomIn() {
    this.zoom *= 1.2
    this.updateZoomLabel()
    this.renderAll()
  }

  zoomOut() {
    this.zoom /= 1.2
    this.updateZoomLabel()
    this.renderAll()
  }

  resetZoom() {
    this.zoom = 1
    this.updateZoomLabel()
    this.renderAll()
  }

  updateZoomLabel() {
    if (this.hasZoomLabelTarget) {
      this.zoomLabelTarget.textContent = `${(this.zoom * 100).toFixed(0)}%`
    }
  }

  performUndo() {
    const state = undo(this.undoStack)
    if (state) {
      this.syncPointInfo = state
      applySyncPoints(this.api, this.syncPointInfo)
      this.renderAll()
    }
    this.updateUndoButtons()
  }

  performRedo() {
    const state = redo(this.undoStack)
    if (state) {
      this.syncPointInfo = state
      applySyncPoints(this.api, this.syncPointInfo)
      this.renderAll()
    }
    this.updateUndoButtons()
  }

  performAutoSync() {
    if (!this.syncPointInfo || !this.api) return
    this.syncPointInfo = autoSync(this.syncPointInfo, this.api)
    this.recordAndApply()
  }

  performResetSyncPoints() {
    if (!this.syncPointInfo || !this.api) return
    this.syncPointInfo = resetSyncPoints(this.api, this.syncPointInfo)
    this.recordAndApply()
  }

  async save() {
    if (!this.syncPointInfo) return

    const flat = toFlatSyncPoints(this.syncPointInfo)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    if (this.hasSaveBtnTarget) this.saveBtnTarget.disabled = true

    try {
      const response = await fetch(`/s/${this.songIdValue}/sync_points`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken,
        },
        body: JSON.stringify({ sync_points: flat }),
      })

      if (response.ok) {
        this.showStatus('Saved')
      } else {
        this.showStatus('Save failed')
      }
    } catch (e) {
      this.showStatus('Save failed')
    } finally {
      if (this.hasSaveBtnTarget) this.saveBtnTarget.disabled = false
    }
  }

  showStatus(msg) {
    if (this.hasStatusMsgTarget) {
      this.statusMsgTarget.textContent = msg
      clearTimeout(this.statusTimeout)
      this.statusTimeout = setTimeout(() => {
        this.statusMsgTarget.textContent = ''
      }, 2000)
    }
  }

  // --- Rendering ---

  renderAll() {
    this.redraw()
    this.renderMarkers()
    this.updateUndoButtons()
    this.updateCursorPosition()
  }

  redraw() {
    if (!this.syncPointInfo || !this.hasCanvasTarget || !this.hasSyncAreaTarget) return

    const area = this.syncAreaTarget
    const canvas = this.canvasTarget
    const width = area.clientWidth
    const height = area.clientHeight

    canvas.width = width
    canvas.height = height

    const virtualWidth =
      timePositionToX(pixelPerMs, this.syncPointInfo.endTime, this.zoom, leftPadding) + leftPadding

    if (this.hasMarkerWrapTarget) {
      this.markerWrapTarget.style.width = `${virtualWidth}px`
      this.markerWrapTarget.style.height = `${height}px`
    }

    drawWaveform(canvas, {
      pixelPerMs,
      leftPadding,
      zoom: this.zoom,
      scrollOffset: area.scrollLeft,
      sampleRate: this.syncPointInfo.sampleRate,
      endTime: this.syncPointInfo.endTime,
      leftSamples: this.syncPointInfo.leftSamples,
      rightSamples: this.syncPointInfo.rightSamples,
      maxAmplitude: this.maxAmplitude,
      width,
      height,
    })
  }

  onScroll() {
    this.redraw()
    this.updateCursorPosition()
  }

  renderMarkers() {
    if (!this.syncPointInfo || !this.hasMarkerWrapTarget) return

    const wrap = this.markerWrapTarget
    wrap.innerHTML = ''

    for (const m of this.syncPointInfo.syncPointMarkers) {
      const el = document.createElement('div')
      const typeName = markerTypeName(m.markerType)
      el.className = `masterbar-marker masterbar-marker-${typeName}${m.syncBpm !== undefined ? ' has-sync-point' : ''}`
      el.style.left = `${timePositionToX(pixelPerMs, m.syncTime, this.zoom, leftPadding)}px`
      el.dataset.markerUniqueId = m.uniqueId

      // Label
      const label = document.createElement('div')
      label.className = 'marker-label'
      label.textContent = buildMarkerLabel(m)
      el.appendChild(label)

      // Head
      const head = document.createElement('div')
      head.className = 'marker-head'

      const arrow = document.createElement('div')
      arrow.className = 'marker-arrow'
      head.appendChild(arrow)

      if (m.markerType !== MarkerType.EndMarker && m.syncBpm) {
        const tempo = document.createElement('div')
        tempo.className = 'marker-tempo'
        tempo.textContent = `${m.syncBpm.toFixed(1)} bpm`
        head.appendChild(tempo)
      }

      el.appendChild(head)

      // Line
      const line = document.createElement('div')
      line.className = 'marker-line'
      el.appendChild(line)

      // Events
      el.addEventListener('mousedown', (e) => this.onMarkerMouseDown(m, e))
      el.addEventListener('dblclick', (e) => this.onMarkerDblClick(m, e))

      wrap.appendChild(el)
    }
  }

  // --- Marker interaction ---

  onMarkerMouseDown(marker, e) {
    if (e.button !== 0 || marker.syncBpm === undefined) return
    e.preventDefault()
    e.stopPropagation()

    this.draggingMarker = marker
    this.dragInfo = { startX: e.pageX, startY: e.pageY, endX: e.pageX }

    document.addEventListener('mousemove', this.boundMouseMove)
    document.addEventListener('mouseup', this.boundMouseUp)
  }

  onMarkerDblClick(marker, e) {
    e.preventDefault()
    e.stopPropagation()
    this.syncPointInfo = toggleMarker(this.syncPointInfo, marker)
    this.recordAndApply()
  }

  onDocumentMouseMove(e) {
    if (!this.draggingMarker || !this.dragInfo || !this.syncPointInfo) return
    e.preventDefault()

    const index = this.syncPointInfo.syncPointMarkers.indexOf(this.draggingMarker)
    if (index === -1) return

    let pageX = e.pageX
    const deltaX = pageX - this.dragInfo.startX

    // Clamp to neighboring sync points
    if (deltaX < 0 && index > 0) {
      const thisX = timePositionToX(pixelPerMs, this.draggingMarker.syncTime, this.zoom, leftPadding)
      const newX = thisX + deltaX

      let prevIdx = index - 1
      while (prevIdx > 0 && !this.syncPointInfo.syncPointMarkers[prevIdx].syncBpm) prevIdx--
      const prevX = timePositionToX(
        pixelPerMs,
        this.syncPointInfo.syncPointMarkers[prevIdx].syncTime,
        this.zoom,
        leftPadding,
      )
      const minX = prevX + dragLimit
      if (newX < minX) pageX = this.dragInfo.startX - (thisX - minX)
    } else if (deltaX > 0 && index < this.syncPointInfo.syncPointMarkers.length - 1) {
      const thisX = timePositionToX(pixelPerMs, this.draggingMarker.syncTime, this.zoom, leftPadding)
      const newX = thisX + deltaX

      let nextIdx = index + 1
      while (
        nextIdx < this.syncPointInfo.syncPointMarkers.length - 1 &&
        !this.syncPointInfo.syncPointMarkers[nextIdx].syncBpm
      ) {
        nextIdx++
      }
      const nextX = timePositionToX(
        pixelPerMs,
        this.syncPointInfo.syncPointMarkers[nextIdx].syncTime,
        this.zoom,
        leftPadding,
      )
      const maxX = nextX - dragLimit
      if (newX > maxX) pageX = this.dragInfo.startX + (maxX - thisX)
    }

    this.dragInfo = { ...this.dragInfo, endX: pageX }

    // Update visual position of dragged marker
    const markerEl = this.markerWrapTarget.querySelector(
      `[data-marker-unique-id="${this.draggingMarker.uniqueId}"]`,
    )
    if (markerEl) {
      const dragDeltaX = this.dragInfo.endX - this.dragInfo.startX
      const baseX = timePositionToX(pixelPerMs, this.draggingMarker.syncTime, this.zoom, leftPadding)
      markerEl.style.left = `${baseX + dragDeltaX}px`
    }
  }

  onDocumentMouseUp(e) {
    document.removeEventListener('mousemove', this.boundMouseMove)
    document.removeEventListener('mouseup', this.boundMouseUp)

    if (!this.draggingMarker || !this.dragInfo) {
      this.draggingMarker = null
      this.dragInfo = null
      return
    }

    e.preventDefault()

    const deltaX = this.dragInfo.endX - this.dragInfo.startX
    if (Math.abs(deltaX) > dragThreshold || (this.draggingMarker.syncBpm !== undefined && Math.abs(deltaX) > 0)) {
      const zoomedPixelPerMs = pixelPerMs * this.zoom
      const deltaTime = deltaX / zoomedPixelPerMs
      const newTimePosition = this.draggingMarker.syncTime + deltaTime
      this.syncPointInfo = moveMarker(this.syncPointInfo, this.draggingMarker, newTimePosition)
      this.recordAndApply()
    }

    this.draggingMarker = null
    this.dragInfo = null
  }

  // Click on waveform background to seek
  onSyncAreaClick(e) {
    if (e.target !== this.markerWrapTarget) return
    const rect = this.markerWrapTarget.getBoundingClientRect()
    const x = e.clientX - rect.left
    const time = xToTimePosition(pixelPerMs, x, this.zoom, leftPadding)
    if (this.api) {
      // Seek via the AlphaTab API - convert time to tick
      const zoomedPixelPerMs = pixelPerMs * this.zoom
      this.api.timePosition = Math.max(0, time)
    }
  }

  // --- Playback cursor ---

  startPlaybackTracking() {
    this.stopPlaybackTracking()
    const tick = () => {
      this.updatePlaybackTime()
      this.animFrameId = requestAnimationFrame(tick)
    }
    this.animFrameId = requestAnimationFrame(tick)
  }

  stopPlaybackTracking() {
    if (this.animFrameId) {
      cancelAnimationFrame(this.animFrameId)
      this.animFrameId = null
    }
  }

  updatePlaybackTime() {
    if (!this.api || !this.hasCursorTarget) return

    // Get the current playback time in ms from the AlphaTab API
    const player = this.api.player
    if (!player) return

    // Use the internal audio element / synth time
    const output = player.output
    if (output && typeof output.currentTime === 'number') {
      this.playbackTime = output.currentTime * 1000
    }

    this.updateCursorPosition()
  }

  updateCursorPosition() {
    if (!this.hasCursorTarget) return
    const x = timePositionToX(pixelPerMs, this.playbackTime, this.zoom, leftPadding)
    this.cursorTarget.style.transform = `translateX(${x}px)`
  }

  // --- Helpers ---

  recordAndApply() {
    storeUndo(this.undoStack, this.syncPointInfo)
    applySyncPoints(this.api, this.syncPointInfo)
    this.renderAll()
  }

  updateUndoButtons() {
    if (this.hasUndoBtnTarget) this.undoBtnTarget.disabled = !canUndo(this.undoStack)
    if (this.hasRedoBtnTarget) this.redoBtnTarget.disabled = !canRedo(this.undoStack)
  }
}
