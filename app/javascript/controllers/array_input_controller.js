import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["list", "template"];

  connect() {
    if (this.listTarget.children.length === 0) { this.addField() }
  }

  addField() {
    const newField = this.templateTarget.content.cloneNode(true);
    this.listTarget.appendChild(newField);
  }

  removeField(event) {
    event.target.closest('.array-input-field').remove();
  }
}
