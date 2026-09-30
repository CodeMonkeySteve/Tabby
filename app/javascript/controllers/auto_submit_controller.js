import { Controller } from "@hotwired/stimulus"

// Submits a form shortly after its inputs change, e.g. for a search box that updates a Turbo Frame
export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  disconnect() {
    clearTimeout(this.timer)
  }

  submit() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  // Leaves blank fields out of the submission (e.g. no `?q=` for a cleared search); use as a `formdata->` action
  omitBlank(event) {
    const entries = [...event.formData]
    for (const [name] of entries) event.formData.delete(name)
    for (const [name, value] of entries) {
      if (value !== "") event.formData.append(name, value)  // rebuilt, as delete removes all of a name's values
    }
  }
}
