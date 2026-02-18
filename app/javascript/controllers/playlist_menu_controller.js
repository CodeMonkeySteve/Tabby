import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["newName"]

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
        form.closest('.dropdown-menu').innerHTML = html
      })
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
        form.closest('.dropdown-menu').innerHTML = html
      })
  }
}
