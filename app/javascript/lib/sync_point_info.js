import * as alphaTab from '@coderline/alphatab'

// Marker types
export const MarkerType = {
  StartMarker: 0,
  EndMarker: 1,
  MasterBar: 2,
  Intermediate: 3,
}

const markerTypeNames = ['startmarker', 'endmarker', 'masterbar', 'intermediate']
export function markerTypeName(type) {
  return markerTypeNames[type]
}

let uidCounter = 0
function uid() {
  return `${Date.now().toString(32)}${(uidCounter++).toString(16)}${Math.random().toString(16).slice(2, 6)}`
}

function ticksToMilliseconds(tick, bpm) {
  return (tick * 60000.0) / (bpm * 960)
}

// --- Coordinate helpers ---

export function timePositionToX(pixelPerMs, time, zoom, padding) {
  return time * pixelPerMs * zoom + padding
}

export function xToTimePosition(pixelPerMs, x, zoom, padding) {
  return (x - padding) / (pixelPerMs * zoom)
}

// --- Undo stack (plain object, no React) ---

export function createUndoStack() {
  return { undos: [], redos: [] }
}

export function storeUndo(stack, info) {
  stack.undos.push(info)
  stack.redos.length = 0
}

export function undo(stack) {
  if (stack.undos.length <= 1) return null
  const state = stack.undos.pop()
  stack.redos.push(state)
  return stack.undos.at(-1)
}

export function redo(stack) {
  if (stack.redos.length === 0) return null
  const state = stack.redos.pop()
  stack.undos.push(state)
  return state
}

export function canUndo(stack) {
  return stack.undos.length > 1
}

export function canRedo(stack) {
  return stack.redos.length > 0
}

// --- Build sync point info from audio ---

export async function buildSyncPointInfoFromAudio(api) {
  const tickCache = api.tickCache
  if (!tickCache || !api.score?.backingTrack?.rawAudioFile) return undefined

  const audioContext = new AudioContext()
  const buffer = await audioContext.decodeAudioData(api.score.backingTrack.rawAudioFile.buffer.slice(0))
  const rawSamples =
    buffer.numberOfChannels === 1
      ? [buffer.getChannelData(0), buffer.getChannelData(0)]
      : [buffer.getChannelData(0), buffer.getChannelData(1)]

  const sampleRate = audioContext.sampleRate
  const endTime = (rawSamples[0].length / sampleRate) * 1000

  await audioContext.close()

  const state = {
    endTick: tickCache.masterBars.at(-1).end,
    syncPointMarkers: [],
    sampleRate,
    leftSamples: rawSamples[0],
    rightSamples: rawSamples[1],
    endTime,
  }

  const createInitialSyncPoints = !api.score.masterBars.some(
    (m) => m.syncPoints && m.syncPoints.length > 0,
  )
  if (createInitialSyncPoints) {
    return autoSync(state, api)
  }

  state.syncPointMarkers = buildSyncPointMarkers(api, false)
  return state
}

// --- Build sync point markers ---

function buildSyncPointMarkers(api, createNewSyncPoints) {
  const markers = []
  const occurences = new Map()

  const syncPointsWithTime = alphaTab.midi.MidiFileGenerator.generateSyncPoints(
    api.score,
    createNewSyncPoints,
  )

  let nextSyncPointIndex = 0
  let synthBpm = api.score.tempo
  let syncBpm = synthBpm
  let synthTick = 0
  let synthTime = 0
  let syncTime = 0

  for (let i = 0; i < api.tickCache.masterBars.length; i++) {
    const masterBar = api.tickCache.masterBars[i]
    const occurence = occurences.get(masterBar.masterBar.index) ?? 0
    occurences.set(masterBar.masterBar.index, occurence + 1)

    const duration = masterBar.end - masterBar.start
    const timeSignatureSteps = duration / masterBar.masterBar.timeSignatureNumerator
    let barTick = masterBar.start
    let tempoChangeIndex = 0

    while (barTick <= masterBar.end) {
      let hasMarkerAtTick = false

      while (
        nextSyncPointIndex < syncPointsWithTime.length &&
        syncPointsWithTime[nextSyncPointIndex].synthTick <= barTick &&
        syncPointsWithTime[nextSyncPointIndex].masterBarIndex === masterBar.masterBar.index &&
        syncPointsWithTime[nextSyncPointIndex].masterBarOccurence === occurence
      ) {
        const syncPoint = syncPointsWithTime[nextSyncPointIndex]

        markers.push({
          uniqueId: uid(),
          masterBarIndex: masterBar.masterBar.index,
          masterBarStart: masterBar.start,
          masterBarEnd: masterBar.end,
          occurence,
          synthTick: syncPoint.synthTick,
          syncTime: syncPoint.syncTime,
          synthTime: syncPoint.synthTime,
          synthBpm: syncPoint.synthBpm,
          syncBpm: syncPoint.syncBpm,
          markerType:
            syncPoint.synthTick === masterBar.start
              ? MarkerType.MasterBar
              : MarkerType.Intermediate,
        })

        if (syncPoint.synthTick === barTick) hasMarkerAtTick = true

        synthBpm = syncPoint.synthBpm
        syncBpm = syncPoint.syncBpm
        synthTime = syncPoint.synthTime
        syncTime = syncPoint.syncTime
        synthTick = syncPoint.synthTick

        nextSyncPointIndex++
      }

      while (
        tempoChangeIndex < masterBar.tempoChanges.length &&
        masterBar.tempoChanges[tempoChangeIndex].tick < barTick
      ) {
        const tickDiff = masterBar.tempoChanges[tempoChangeIndex].tick - synthTick
        if (tickDiff > 0) {
          synthTime += ticksToMilliseconds(tickDiff, synthBpm)
          syncTime += ticksToMilliseconds(tickDiff, syncBpm)
        }
        synthTick += tickDiff
        tempoChangeIndex++
      }

      const tickDiff = barTick - synthTick
      if (tickDiff > 0) {
        synthTime += ticksToMilliseconds(tickDiff, synthBpm)
        syncTime += ticksToMilliseconds(tickDiff, syncBpm)
      }
      synthTick = barTick

      if (!hasMarkerAtTick && barTick < masterBar.end) {
        markers.push({
          uniqueId: uid(),
          masterBarIndex: masterBar.masterBar.index,
          masterBarStart: masterBar.start,
          masterBarEnd: masterBar.end,
          occurence,
          synthTick: barTick,
          syncTime,
          synthTime,
          synthBpm,
          markerType:
            barTick === masterBar.start ? MarkerType.MasterBar : MarkerType.Intermediate,
        })
      }

      barTick += timeSignatureSteps
    }
  }

  // End marker
  const lastMasterBar = api.tickCache.masterBars.at(-1)
  const lastSyncPoint = markers.at(-1)
  if (lastMasterBar.end > lastSyncPoint.synthTick) {
    const tickDiff = lastMasterBar.end - synthTick
    if (tickDiff > 0) {
      synthTime += ticksToMilliseconds(tickDiff, synthBpm)
      syncTime += ticksToMilliseconds(tickDiff, syncBpm)
    }
    synthTick = lastMasterBar.end

    markers.push({
      uniqueId: uid(),
      masterBarIndex: lastMasterBar.masterBar.index,
      masterBarStart: lastMasterBar.start,
      masterBarEnd: lastMasterBar.end,
      occurence: occurences.get(lastMasterBar.masterBar.index) - 1,
      synthTick,
      syncTime,
      synthTime,
      synthBpm,
      markerType: MarkerType.EndMarker,
    })
  } else {
    lastSyncPoint.markerType = MarkerType.EndMarker
  }

  return markers
}

// --- Audio silence detection ---

function findAudioStartAndEnd(state) {
  const nonSilentSamplesThreshold = 1 * state.sampleRate
  const silentSamplesThreshold = 0.2 * state.sampleRate
  const nonSilentAmplitudeThreshold = 0.001
  const searchThreshold = Math.min(10 * state.sampleRate, state.leftSamples.length * 0.1)

  let songStart = searchThreshold
  let songEnd = state.leftSamples.length - searchThreshold

  // Find start
  let sampleIndex = 0
  let nonSilentSamplesInSection = 0
  let silentSamplesInSequence = 0
  let sectionStart = 0

  while (sampleIndex < songStart) {
    if (
      Math.abs(state.leftSamples[sampleIndex]) >= nonSilentAmplitudeThreshold ||
      Math.abs(state.rightSamples[sampleIndex]) >= nonSilentAmplitudeThreshold
    ) {
      if (nonSilentSamplesInSection === 0) sectionStart = sampleIndex
      nonSilentSamplesInSection++
      silentSamplesInSequence = 0
    } else {
      silentSamplesInSequence++
    }

    if (silentSamplesInSequence > silentSamplesThreshold) {
      sectionStart = sampleIndex + 1
      nonSilentSamplesInSection = 0
      silentSamplesInSequence = 0
    } else if (nonSilentSamplesInSection > nonSilentSamplesThreshold) {
      songStart = sectionStart
      break
    }
    sampleIndex++
  }

  // Find end
  sampleIndex = state.leftSamples.length - 1
  nonSilentSamplesInSection = 0
  silentSamplesInSequence = 0
  sectionStart = sampleIndex

  while (sampleIndex >= songEnd) {
    if (
      Math.abs(state.leftSamples[sampleIndex]) >= nonSilentAmplitudeThreshold ||
      Math.abs(state.rightSamples[sampleIndex]) >= nonSilentAmplitudeThreshold
    ) {
      if (nonSilentSamplesInSection === 0) sectionStart = sampleIndex
      nonSilentSamplesInSection++
      silentSamplesInSequence = 0
    } else {
      silentSamplesInSequence++
    }

    if (silentSamplesInSequence > silentSamplesThreshold) {
      sectionStart = sampleIndex - 1
      nonSilentSamplesInSection = 0
      silentSamplesInSequence = 0
    } else if (nonSilentSamplesInSection > nonSilentSamplesThreshold) {
      songEnd = sectionStart
      break
    }
    sampleIndex--
  }

  return [(songStart / state.sampleRate) * 1000, (songEnd / state.sampleRate) * 1000]
}

// --- Auto sync ---

export function autoSync(oldState, api, padToAudio = true) {
  const state = {
    endTick: api.tickCache.masterBars.at(-1).end,
    syncPointMarkers: [],
    sampleRate: oldState.sampleRate,
    leftSamples: oldState.leftSamples,
    rightSamples: oldState.rightSamples,
    endTime: oldState.endTime,
  }

  state.syncPointMarkers = buildSyncPointMarkers(api, true)

  if (padToAudio) {
    const [songStart, songEnd] = findAudioStartAndEnd(state)
    const synthDuration = state.syncPointMarkers.at(-1).synthTime
    const realDuration = songEnd - songStart
    const scaleFactor = realDuration / synthDuration

    state.syncPointMarkers.at(0).syncBpm = state.syncPointMarkers.at(0).synthBpm
    state.syncPointMarkers.at(-1).syncBpm = state.syncPointMarkers.at(-1).synthBpm

    // 1st Pass: shift tempo change markers
    const syncPoints = state.syncPointMarkers.filter((m) => m.syncBpm !== undefined)
    let syncTimePos = songStart
    for (let i = 0; i < syncPoints.length; i++) {
      const sp = syncPoints[i]
      sp.syncTime = syncTimePos

      if (i > 0) {
        const prev = syncPoints[i - 1]
        const sd = sp.synthTime - prev.synthTime
        const cd = sp.syncTime - prev.syncTime
        prev.syncBpm = (sd / cd) * prev.synthBpm
      }

      const ownStart = sp.synthTime
      const nextStart = i < syncPoints.length - 1 ? syncPoints[i + 1].synthTime : ownStart
      const oldDuration = nextStart - ownStart
      syncTimePos += oldDuration * scaleFactor
    }

    // 2nd Pass: adjust in-between markers
    syncTimePos = songStart
    let syncedBpm = syncPoints[0].syncBpm
    for (let i = 0; i < state.syncPointMarkers.length; i++) {
      const marker = state.syncPointMarkers[i]
      marker.syncTime = syncTimePos

      if (marker.syncBpm) syncedBpm = marker.syncBpm

      if (i < state.syncPointMarkers.length - 1) {
        const tickDiff = state.syncPointMarkers[i + 1].synthTick - marker.synthTick
        syncTimePos += ticksToMilliseconds(tickDiff, syncedBpm)
      }
    }
  }

  return state
}

// --- Update after modification ---

export function updateSyncPointsAfterModification(modifiedIndex, s, isDelete, cloneMarkers) {
  let startIndexForUpdate = Math.max(0, modifiedIndex - 1)
  while (startIndexForUpdate > 0 && !s.syncPointMarkers[startIndexForUpdate].syncBpm) {
    startIndexForUpdate--
  }

  let nextIndexForUpdate = Math.min(s.syncPointMarkers.length - 1, modifiedIndex + 1)
  while (
    nextIndexForUpdate < s.syncPointMarkers.length - 1 &&
    !s.syncPointMarkers[nextIndexForUpdate].syncBpm
  ) {
    nextIndexForUpdate++
  }

  const modifiedMarker = s.syncPointMarkers[modifiedIndex]
  let newBpmBefore = modifiedMarker.synthBpm

  if (isDelete) {
    if (nextIndexForUpdate > modifiedIndex) {
      const previousMarker = cloneMarkers
        ? { ...s.syncPointMarkers[startIndexForUpdate] }
        : s.syncPointMarkers[startIndexForUpdate]
      s.syncPointMarkers[startIndexForUpdate] = previousMarker

      const nextMarker = s.syncPointMarkers[nextIndexForUpdate]
      if (nextMarker.syncBpm) {
        const synthDuration = nextMarker.synthTime - previousMarker.synthTime
        const syncedDuration = nextMarker.syncTime - previousMarker.syncTime
        newBpmBefore = (synthDuration / syncedDuration) * previousMarker.synthBpm
      } else {
        nextIndexForUpdate++
      }

      previousMarker.syncBpm = newBpmBefore
      for (let i = startIndexForUpdate + 1; i < nextIndexForUpdate; i++) {
        const newMarker = cloneMarkers ? { ...s.syncPointMarkers[i] } : s.syncPointMarkers[i]
        s.syncPointMarkers[i] = newMarker
        const tickDuration = newMarker.synthTick - previousMarker.synthTick
        newMarker.syncTime =
          previousMarker.syncTime + ticksToMilliseconds(tickDuration, newBpmBefore)
      }
    }
  } else {
    // Move: adjust before and after
    if (startIndexForUpdate < modifiedIndex) {
      const previousMarker = cloneMarkers
        ? { ...s.syncPointMarkers[startIndexForUpdate] }
        : s.syncPointMarkers[startIndexForUpdate]
      s.syncPointMarkers[startIndexForUpdate] = previousMarker
      const synthDuration = modifiedMarker.synthTime - previousMarker.synthTime
      const syncedDuration = modifiedMarker.syncTime - previousMarker.syncTime
      newBpmBefore = (synthDuration / syncedDuration) * previousMarker.synthBpm
      previousMarker.syncBpm = newBpmBefore

      let syncedTimePosition = previousMarker.syncTime
      for (let i = startIndexForUpdate; i < modifiedIndex; i++) {
        const marker = cloneMarkers ? { ...s.syncPointMarkers[i] } : s.syncPointMarkers[i]
        s.syncPointMarkers[i] = marker
        marker.syncTime = syncedTimePosition

        if (i < modifiedIndex - 1) {
          const tickDuration = s.syncPointMarkers[i + 1].synthTick - marker.synthTick
          syncedTimePosition += ticksToMilliseconds(tickDuration, newBpmBefore)
        }
      }
    }

    if (nextIndexForUpdate > modifiedIndex) {
      const nextMarker = s.syncPointMarkers[nextIndexForUpdate]
      let newBpmAfter
      if (nextMarker.syncBpm) {
        const synthDuration = nextMarker.synthTime - modifiedMarker.synthTime
        const syncedDuration = nextMarker.syncTime - modifiedMarker.syncTime
        newBpmAfter =
          syncedDuration > 0 ? (synthDuration / syncedDuration) * modifiedMarker.synthBpm : 0
      } else {
        newBpmAfter = newBpmBefore
        nextIndexForUpdate++
      }

      modifiedMarker.syncBpm = newBpmAfter
      const tickDuration = s.syncPointMarkers[modifiedIndex + 1].synthTick - modifiedMarker.synthTick
      let syncedTimePosition =
        modifiedMarker.syncTime + ticksToMilliseconds(tickDuration, newBpmAfter)

      for (let i = modifiedIndex + 1; i < nextIndexForUpdate; i++) {
        const marker = cloneMarkers ? { ...s.syncPointMarkers[i] } : s.syncPointMarkers[i]
        s.syncPointMarkers[i] = marker
        marker.syncTime = syncedTimePosition

        if (i < nextIndexForUpdate - 1) {
          const tickDuration = s.syncPointMarkers[i + 1].synthTick - marker.synthTick
          syncedTimePosition += ticksToMilliseconds(tickDuration, newBpmAfter)
        }
      }
    }
  }
}

// --- Move / toggle ---

export function moveMarker(s, marker, newTimePosition) {
  const markerIndex = s.syncPointMarkers.findIndex((m) => m === marker)
  const newS = { ...s, syncPointMarkers: [...s.syncPointMarkers] }
  newS.syncPointMarkers[markerIndex] = {
    ...newS.syncPointMarkers[markerIndex],
    syncTime: Math.max(0, newTimePosition),
  }
  updateSyncPointsAfterModification(markerIndex, newS, false, true)
  return newS
}

export function toggleMarker(s, marker) {
  if (marker.markerType === MarkerType.StartMarker || marker.markerType === MarkerType.EndMarker) {
    return s
  }

  const markerIndex = s.syncPointMarkers.indexOf(marker)
  if (markerIndex === -1) return s

  const newS = { ...s, syncPointMarkers: [...s.syncPointMarkers] }
  if (marker.syncBpm) {
    newS.syncPointMarkers[markerIndex] = { ...marker, syncBpm: undefined }
    updateSyncPointsAfterModification(markerIndex, newS, true, true)
  } else {
    updateSyncPointsAfterModification(markerIndex, newS, false, true)
  }

  return newS
}

// --- Reset ---

export function resetSyncPoints(api, state) {
  for (const b of api.score.masterBars) {
    b.syncPoints = undefined
  }
  return { ...state, syncPointMarkers: buildSyncPointMarkers(api, false) }
}

// --- Apply / flatten ---

export function applySyncPoints(api, syncPointInfo) {
  const flatSyncPoints = toFlatSyncPoints(syncPointInfo)
  const tickPosition = api.tickPosition
  api.score.applyFlatSyncPoints(flatSyncPoints)
  api.updateSyncPoints()
  api.tickPosition = tickPosition
}

export function toFlatSyncPoints(syncPointInfo) {
  const flat = []
  for (const m of syncPointInfo.syncPointMarkers) {
    if (m.syncBpm) {
      const duration = m.masterBarEnd - m.masterBarStart
      const ratioPosition = (m.synthTick - m.masterBarStart) / duration
      flat.push({
        barIndex: m.masterBarIndex,
        barOccurence: m.occurence,
        barPosition: ratioPosition,
        millisecondOffset: m.syncTime | 0,
      })
    }
  }
  return flat
}

// --- Waveform drawing ---

const waveformDefaults = {
  barNumberHeight: 20,
  arrowHeight: 20,
  timeAxisHeight: 20,
  timeAxisSubSecondTickHeight: 5,
  timeAxisLineColor: '#A5A5A5',
  waveFormColor: '#436d9d99',
  leftPadding: 0,
  zoom: 1,
  scrollOffset: 0,
}

function drawFrame(ctx, opts, info) {
  ctx.fillStyle = opts.timeAxisLineColor
  ctx.fillRect(0, info.waveFormY + 2 * info.halfHeight, ctx.canvas.width, 1)
  ctx.fillRect(0, opts.barNumberHeight, ctx.canvas.width, 1)
  ctx.fillRect(0, info.waveFormY, ctx.canvas.width, 1)
  ctx.fillRect(0, info.waveFormY + info.halfHeight, ctx.canvas.width, 1)
}

function drawSamples(ctx, opts, info) {
  ctx.save()
  ctx.translate(-opts.scrollOffset, 0)
  ctx.beginPath()

  const startX = Math.max(opts.scrollOffset - opts.leftPadding, 0)
  const endX = startX + ctx.canvas.width + opts.leftPadding
  const samplesPerPixel = opts.sampleRate / (info.zoomedPixelPerMs * 1000)

  for (let x = startX; x < endX; x++) {
    const startSample = (x * samplesPerPixel) | 0
    const endSample = ((x + 1) * samplesPerPixel) | 0

    let maxTop = 0
    let maxBottom = 0
    for (let sample = startSample; sample <= endSample; sample++) {
      const magnitudeTop = Math.abs(opts.leftSamples[sample] / opts.maxAmplitude || 0)
      const magnitudeBottom = Math.abs(opts.rightSamples[sample] / opts.maxAmplitude || 0)
      if (magnitudeTop > maxTop) maxTop = magnitudeTop
      if (magnitudeBottom > maxBottom) maxBottom = magnitudeBottom
    }

    const topBarHeight = Math.min(info.halfHeight, Math.round(maxTop * info.halfHeight))
    const bottomBarHeight = Math.min(info.halfHeight, Math.round(maxBottom * info.halfHeight))
    const barHeight = topBarHeight + bottomBarHeight || 1
    ctx.rect(x + opts.leftPadding, info.waveFormY + (info.halfHeight - topBarHeight), 1, barHeight)
  }

  ctx.fillStyle = opts.waveFormColor
  ctx.fill()
  ctx.restore()
}

function drawTimeAxis(ctx, opts, info) {
  ctx.save()
  ctx.translate(-opts.scrollOffset, 0)

  ctx.fillStyle = opts.timeAxisLineColor
  const style = window.getComputedStyle(ctx.canvas)
  ctx.font = style.font
  ctx.textAlign = 'left'
  ctx.textBaseline = 'bottom'

  const timeAxisY = info.waveFormY + 2 * info.halfHeight
  const leftTimeSecond = Math.floor(
    (info.startX - opts.leftPadding) / info.zoomedPixelPerMs / 1000,
  )
  const rightTimeSecond = Math.ceil(info.endX / info.zoomedPixelPerMs / 1000)

  let time = leftTimeSecond * 1000
  const rightTime = rightTimeSecond * 1000

  while (time <= rightTime) {
    const timeX = timePositionToX(opts.pixelPerMs, time, opts.zoom, opts.leftPadding)
    ctx.fillRect(timeX, timeAxisY, 1, opts.timeAxisHeight)

    const totalSeconds = Math.abs(time / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = Math.floor(totalSeconds - minutes * 60)
    const sign = time < 0 ? '-' : ''
    const minutesText = minutes.toString().padStart(2, '0')
    const secondsText = seconds.toString().padStart(2, '0')

    ctx.fillText(`${sign}${minutesText}:${secondsText}`, timeX + 3, timeAxisY + opts.timeAxisHeight)

    const nextSecond = time + 1000
    while (time < nextSecond) {
      const subSecondX = timePositionToX(opts.pixelPerMs, time, opts.zoom, opts.leftPadding)
      ctx.fillRect(subSecondX, timeAxisY, 1, opts.timeAxisSubSecondTickHeight)
      time += 100
    }
  }

  ctx.restore()
}

export function drawWaveform(canvas, options) {
  const opts = { ...waveformDefaults, ...options }
  const ctx = canvas.getContext('2d')
  ctx.clearRect(0, 0, canvas.width, canvas.height)
  ctx.save()

  const waveFormY = opts.barNumberHeight + opts.arrowHeight
  const halfHeight = ((ctx.canvas.height - waveFormY - opts.timeAxisHeight) / 2) | 0
  const startX = Math.max(opts.scrollOffset - opts.leftPadding, 0)
  const endX = startX + ctx.canvas.width + opts.leftPadding
  const zoomedPixelPerMs = opts.pixelPerMs * opts.zoom

  const info = { waveFormY, halfHeight, startX, endX, zoomedPixelPerMs }

  drawFrame(ctx, opts, info)
  drawSamples(ctx, opts, info)
  drawTimeAxis(ctx, opts, info)
}

export function computeMaxAmplitude(leftSamples, rightSamples) {
  let max = 0
  for (let i = 0; i < leftSamples.length; i++) {
    let s = Math.abs(leftSamples[i])
    if (s > max) max = s
    s = Math.abs(rightSamples[i])
    if (s > max) max = s
  }
  return max === 0 ? 1 : max
}

// --- Marker label ---

export function buildMarkerLabel(m) {
  switch (m.markerType) {
    case MarkerType.StartMarker:
      return 'Start'
    case MarkerType.EndMarker:
      return 'End'
    case MarkerType.MasterBar:
      if (m.occurence > 0) return `${m.masterBarIndex + 1} (${m.occurence + 1})`
      return `${m.masterBarIndex + 1}`
    case MarkerType.Intermediate:
      return ''
  }
}
