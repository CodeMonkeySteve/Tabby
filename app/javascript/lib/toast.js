// Shows an error message in a Bootstrap toast, from the layout's template, removing it once hidden
export function showError(message) {
  const container = document.getElementById('toasts')
  const template = document.getElementById('error-toast')
  if (!container || !template) return

  const toast = template.content.firstElementChild.cloneNode(true)
  toast.querySelector('.toast-body').textContent = message
  toast.addEventListener('hidden.bs.toast', () => toast.remove())
  container.append(toast)
  window.bootstrap.Toast.getOrCreateInstance(toast).show()
}
