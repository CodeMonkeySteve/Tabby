import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["newName"]
  static values = { song: String }

  toggle(ev) {
    const el = ev.currentTarget
    const body = { playlist: el.value, checked: el.checked };

    const form = this.element;
    fetch(form.action, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify(body)
    })
      .then(response => response.text())
      .then(html => {
        this.replaceMenus(html)
      })
  }

  // Replaces the song's menus with the updated one, including any other copies of the song on the page, and colors their
  // toggles' icons by whether the song is in any playlist (see ApplicationHelper#playlist_icon_attributes)
  replaceMenus(html) {
    const song = CSS.escape(this.songValue)
    for (const form of document.querySelectorAll(`form[data-playlist-menu-song-value="${song}"]`)) {
      form.closest('.dropdown-menu').innerHTML = html
    }
    const menu = document.createElement('template')
    menu.innerHTML = html
    const inPlaylist = menu.content.querySelector('input[type=checkbox]:checked') !== null
    for (const icon of document.querySelectorAll(`.playlist-icon[data-song="${song}"]`)) {
      icon.classList.toggle('text-success', inPlaylist)
    }
  }

  // Enter in the new playlist name creates it, instead of submitting the form and leaving the page
  save(ev) {
    ev.preventDefault()
    this.create()
  }

  create() {
    const name = this.newNameTarget.value.trim()
    if (!name) return

    const form = this.element
    const formData = new FormData(form)
    formData.set('new_playlist_name', name)

    fetch(form.action, {
      method: 'POST',
      headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content },
      body: formData
    })
      .then(response => response.text())
      .then(html => {
        this.replaceMenus(html)
      })
  }
}
