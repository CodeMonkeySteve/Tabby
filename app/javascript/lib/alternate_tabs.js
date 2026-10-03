import { sameTuning } from 'lib/track_tab'

// How long after the last string change it's saved
const SAVE_DELAY = 1000

// keepalive requests are limited to 64KB in all
const KEEPALIVE_LIMIT = 60_000

// The user's alternate tabs for a song (see AlternateTab), as { id, trackIndex, tuning, noteCount, strings, optimizer }.  Changes
// apply here at once and are saved to the server: new and replaced tabs right away, and string changes batched a second after
// the last one.  Failed saves are retried with the next.
export default class AlternateTabs {
  constructor(songId, tabs = [], { onError = () => {} } = {}) {
    this.url = `/s/${songId}/alt`
    this.tabs = tabs.map(tab => ({ ...tab, strings: { ...tab.strings } }))
    this.onError = onError
    this.pending = new Map()  // the unsaved string changes of saved tabs
    this.timer = null
  }

  find(trackIndex, tuning) {
    return this.tabs.find(tab => tab.trackIndex === trackIndex && sameTuning(tab.tuning, tuning))
  }

  // Adds the tab for a track and tuning (replacing any), saving it
  add(trackIndex, tuning, noteCount, strings = {}, optimizer = null) {
    const existing = this.find(trackIndex, tuning)
    if (existing) this.forget(existing)
    const tab = { id: null, trackIndex, tuning: [...tuning], noteCount, strings: { ...strings }, optimizer }
    this.tabs.push(tab)
    this.create(tab)
    return tab
  }

  // Replaces a tab's strings, e.g. with a new fingering, saving them
  replace(tab, strings, optimizer) {
    Object.assign(tab, { strings: { ...strings }, optimizer })
    if (tab.id) this.put(tab)
    else this.create(tab)
  }

  remove(tab) {
    this.forget(tab)
    if (tab.id) this.send('DELETE', `${this.url}/${tab.id}`).catch(error => this.failed(tab, error))
  }

  // Changes strings by note index (null for the score's string), saving them shortly
  edit(tab, changes) {
    for (const [index, string] of Object.entries(changes)) {
      if (string === null) delete tab.strings[index]
      else tab.strings[index] = string
    }
    this.pending.set(tab, { ...this.pending.get(tab), ...changes })
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.flush(), SAVE_DELAY)
  }

  // Saves unsaved tabs and changes now (keepalive lets them finish while the page unloads)
  flush({ keepalive = false } = {}) {
    clearTimeout(this.timer)
    const saves = this.tabs.filter(tab => !tab.id && !tab.saving).map(tab => this.create(tab, { keepalive }))
    saves.push(...this.tabs.filter(tab => tab.id && tab.unreplaced).map(tab => this.put(tab, { keepalive })))
    for (const [tab, changes] of this.pending) {
      if (!tab.id) continue  // saved with the tab
      this.pending.delete(tab)
      saves.push(this.send('PATCH', `${this.url}/${tab.id}`, { strings: changes }, { keepalive }).catch(error => {
        this.pending.set(tab, { ...changes, ...this.pending.get(tab) })
        this.failed(tab, error)
      }))
    }
    return Promise.all(saves)
  }

  // POSTs a whole tab, then any changes made meanwhile
  async create(tab, { keepalive = false } = {}) {
    const { trackIndex: track_index, tuning, noteCount: note_count, strings, optimizer } = tab
    this.pending.delete(tab)
    tab.saving = true
    try {
      const response = await this.send('POST', this.url, { track_index, tuning, note_count, strings, optimizer }, { keepalive })
      tab.id = (await response.json()).id
      if (this.pending.has(tab)) this.flush()
    } catch (error) {
      this.failed(tab, error)
    } finally {
      tab.saving = false
    }
  }

  // PUTs a tab's whole strings, marking it to be PUT again with the next save if that fails
  async put(tab, { keepalive = false } = {}) {
    const { strings, optimizer } = tab
    this.pending.delete(tab)
    tab.unreplaced = false
    try {
      await this.send('PUT', `${this.url}/${tab.id}`, { strings, optimizer }, { keepalive })
    } catch (error) {
      tab.unreplaced = true
      this.failed(tab, error)
    }
  }

  forget(tab) {
    this.tabs.splice(this.tabs.indexOf(tab), 1)
    this.pending.delete(tab)
  }

  failed(tab, error) {
    console.error('Failed to save alternate tab', error)
    this.onError(tab, error)
  }

  async send(method, url, body = null, { keepalive = false } = {}) {
    const json = body && JSON.stringify({ alternate_tab: body })
    const response = await fetch(url, {
      method,
      keepalive: keepalive && (json?.length ?? 0) < KEEPALIVE_LIMIT,
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': globalThis.document?.querySelector('meta[name="csrf-token"]')?.content,
      },
      body: json,
    })
    if (!response.ok) throw new Error(`${method} ${url} failed: ${response.status}`)
    return response
  }
}
