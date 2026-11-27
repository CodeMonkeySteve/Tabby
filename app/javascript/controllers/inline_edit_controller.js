import { Controller } from "@hotwired/stimulus"

// Edits a form's field in place, like a page title: saves it when changed, or restores it on Escape or when it's invalid
export default class extends Controller {
  static targets = ['input']

  // Saves on Enter by leaving the field (see save), rather than also submitting the form implicitly
  commit(event) {
    event.preventDefault()
    this.inputTarget.blur()
  }

  cancel() {
    this.inputTarget.value = this.inputTarget.defaultValue
    this.inputTarget.blur()
  }

  save() {
    if (this.inputTarget.checkValidity()) {
      this.element.requestSubmit()
    } else {
      this.cancel()
    }
  }
}
