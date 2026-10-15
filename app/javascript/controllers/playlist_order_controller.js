import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { showError } from "lib/toast"

// Reorders a playlist's songs by dragging them, saving the new order (see PlaylistsController#order)
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      draggable: '[data-song-id]',
      handle: '.drag-handle',
      dataIdAttr: 'data-song-id',
      animation: 150,
      // keeps the songs above other items, like the edit link
      onMove: ev => 'songId' in ev.related.dataset,
      onStart: () => { this.previousOrder = this.sortable.toArray() },
      onUpdate: () => this.save(this.previousOrder)
    })
  }

  disconnect() {
    this.sortable.destroy()
  }

  // Saves the songs' order, restoring the previous order if it can't be saved
  async save(previousOrder) {
    const songIds = Array.from(this.element.querySelectorAll('[data-song-id]'), el => el.dataset.songId)
    try {
      const response = await fetch(this.urlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ song_ids: songIds })
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
    } catch (error) {
      console.error("Can't save the playlist order", error)
      this.sortable.sort(previousOrder, true)
      showError("Couldn't save the playlist order")
    }
  }
}
