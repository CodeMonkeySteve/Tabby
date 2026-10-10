// The player's tab edit mode: selecting a note (by clicking it, or with ←/→) and moving it, with the notes connected to it, to
// another string (with ↑/↓, or the buttons beside it), keeping its pitch.  The player supplies the callbacks:
// - locate(note): the { trackTab, index } of an AlphaTab note on a stringed staff, or null
// - context(trackTab): the track's current { tuning, strings } (see TrackTab#moveTarget)
// - move(trackTab, index, string): moves the note's chain to the string
export default class TabEditor {
  constructor(api, viewport, { locate, context, move }) {
    Object.assign(this, { api, viewport, locate, context, move })
    this.active = false
    this.selection = null  // the selected { trackTab, index }
    this.noteDown = false  // whether the current click is on a note
    this.overlay = this.buildOverlay()

    api.noteMouseDown.on(note => this.handleNoteDown(note))
    api.postRenderFinished.on(() => this.position())  // once the new render's bounds are known (from the worker)
    this.clickHandler = () => this.handleClick()
    viewport.addEventListener('click', this.clickHandler)
  }

  destroy() {
    this.viewport.removeEventListener('click', this.clickHandler)
    this.overlay.remove()
  }

  setActive(active) {
    this.active = active
    this.api.settings.player.enableUserInteraction = !active  // no seeking or range selection while editing
    if (!active) this.select(null)
  }

  // Handles a key while a note is selected, returning whether it did
  handleKey(e) {
    if (!this.active || !this.selection) return false
    switch (e.key) {
      case 'ArrowUp': this.moveSelection(1); break
      case 'ArrowDown': this.moveSelection(-1); break
      case 'ArrowLeft': this.step(-1); break
      case 'ArrowRight': this.step(1); break
      case 'Escape': this.select(null); break
      default: return false
    }
    return true
  }

  handleNoteDown(note) {
    if (!this.active) return
    const selection = this.locate(note)
    if (!selection) return
    this.noteDown = true
    this.select(selection)
  }

  // Clears the selection on a click away from the notes
  handleClick() {
    if (this.active && !this.noteDown) this.select(null)
    this.noteDown = false
  }

  select(selection) {
    this.selection = selection
    this.position()
  }

  // Selects the previous (-1) or next (1) note of the track, scrolling it into view
  step(delta) {
    const { trackTab, index } = this.selection
    const next = index + delta
    if (next < 0 || next >= trackTab.notes.length) return
    this.select({ trackTab, index: next })
    // in each staff, ending with the tab number's (the first, since they're prepended) beside the buttons, so it wins if they
    // don't all fit; their scroll margin clears the buttons and the dock
    for (const box of [...this.overlay.querySelectorAll('.at-tab-note.selected')].reverse()) {
      box.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' })
    }
  }

  // Moves the selected note's chain to the next string up (1) or down (-1) it can be played on, or flashes if there's none
  moveSelection(direction) {
    const { trackTab, index } = this.selection
    const { tuning, strings } = this.context(trackTab)
    const string = trackTab.moveTarget(index, tuning, strings, direction)
    if (string === null) this.flash()
    else this.move(trackTab, index, string)
  }

  flash() {
    this.overlay.classList.remove('flash')
    void this.overlay.offsetWidth  // restarts the animation
    this.overlay.classList.add('flash')
  }

  buildOverlay() {
    const overlay = document.createElement('div')
    overlay.className = 'at-tab-selection d-none'
    overlay.innerHTML = `
      <div class="at-tab-selection-buttons btn-group-vertical">
        <button type="button" class="btn btn-sm btn-light" data-direction="1" title="Higher String (Up Arrow)">
          <i class="fas fa-caret-up"></i>
        </button>
        <button type="button" class="btn btn-sm btn-light" data-direction="-1" title="Lower String (Down Arrow)">
          <i class="fas fa-caret-down"></i>
        </button>
      </div>`
    overlay.addEventListener('click', e => {
      const button = e.target.closest('[data-direction]')
      if (!button) return
      e.stopPropagation()
      this.moveSelection(Number(button.dataset.direction))
    })
    this.viewport.append(overlay)
    return overlay
  }

  // Outlines the selected note (in each staff showing it) and, more lightly, the rest of its chain, with the buttons beside it
  position() {
    for (const box of this.overlay.querySelectorAll('.at-tab-note')) box.remove()
    const { trackTab, index } = this.selection ?? {}
    const selected = trackTab ? this.noteBounds(trackTab.notes[index]) : []
    this.overlay.classList.toggle('d-none', selected.length === 0)
    if (selected.length === 0) return

    const surface = this.api.canvasElement.element.getBoundingClientRect()
    const viewport = this.viewport.getBoundingClientRect()
    const offset = { x: surface.left - viewport.left, y: surface.top - viewport.top }
    const chain = trackTab.chainNotes[trackTab.chains[index]].filter(i => i !== index)
    for (const bounds of chain.flatMap(i => this.noteBounds(trackTab.notes[i]))) this.addBox(bounds, offset, 'chained')
    for (const bounds of selected) this.addBox(bounds, offset, 'selected')

    const last = selected.at(-1)
    const buttons = this.overlay.querySelector('.at-tab-selection-buttons')
    buttons.style.left = `${offset.x + last.x + last.w + 4}px`
    buttons.style.top = `${offset.y + last.y + last.h / 2}px`
  }

  addBox(bounds, offset, kind) {
    const box = document.createElement('div')
    box.className = `at-tab-note ${kind}`
    Object.assign(box.style, {
      left: `${offset.x + bounds.x - 2}px`,
      top: `${offset.y + bounds.y - 2}px`,
      width: `${bounds.w + 4}px`,
      height: `${bounds.h + 4}px`,
    })
    this.overlay.prepend(box)
  }

  // The rendered bounds of a note (its tab number, and its head on a standard staff), relative to the score's surface
  noteBounds(note) {
    return (this.api.boundsLookup?.findBeats(note.beat) ?? [])
      .flatMap(beat => beat.notes ?? [])
      .filter(bounds => bounds.note === note)
      .map(bounds => bounds.noteHeadBounds)
  }
}
