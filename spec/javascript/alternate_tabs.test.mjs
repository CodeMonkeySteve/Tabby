import assert from 'node:assert/strict'
import { afterEach, beforeEach, mock, test } from 'node:test'
import AlternateTabs from 'lib/alternate_tabs'

const STANDARD = [43, 38, 33, 28]
const FIVE_STRING = [43, 38, 33, 28, 23]
const saved = (overrides = {}) => ({
  id: 'tab-1', trackIndex: 0, tuning: STANDARD, noteCount: 10, strings: {}, optimizer: null, ...overrides,
})

let requests
let failing

// Records each request (with its alternate_tab body), answering POSTs with a new id, or failing while `failing` is set
beforeEach(() => {
  requests = []
  failing = false
  mock.timers.enable({ apis: ['setTimeout'] })
  mock.method(console, 'error', () => {})
  globalThis.fetch = async (url, { method, body, keepalive }) => {
    requests.push({ method, url, body: body && JSON.parse(body).alternate_tab, keepalive })
    const status = failing ? 500 : method === 'POST' ? 201 : 204
    return { ok: status < 400, status, json: async () => ({ id: `tab-${requests.length + 1}` }) }
  }
})

afterEach(() => {
  mock.timers.reset()
  mock.restoreAll()
})

const settle = () => new Promise(resolve => setImmediate(resolve))

test('finds tabs by track and tuning', () => {
  const tabs = new AlternateTabs('song', [saved(), saved({ id: 'tab-2', tuning: FIVE_STRING })])
  assert.equal(tabs.find(0, FIVE_STRING).id, 'tab-2')
  assert.equal(tabs.find(1, STANDARD), undefined)
})

test('saves new, replaced, and removed tabs', async () => {
  const tabs = new AlternateTabs('song')
  const tab = tabs.add(0, FIVE_STRING, 10, { 3: 2 }, 'beam')
  assert.equal(tabs.find(0, FIVE_STRING), tab)
  await settle()
  assert.equal(tab.id, 'tab-2')

  tabs.replace(tab, { 4: 1 }, 'beam')
  tabs.remove(tab)
  await settle()
  assert.deepEqual(requests, [
    {
      method: 'POST', url: '/s/song/alt', keepalive: false,
      body: { track_index: 0, tuning: FIVE_STRING, note_count: 10, strings: { 3: 2 }, optimizer: 'beam' },
    },
    { method: 'PUT', url: '/s/song/alt/tab-2', body: { strings: { 4: 1 }, optimizer: 'beam' }, keepalive: false },
    { method: 'DELETE', url: '/s/song/alt/tab-2', body: null, keepalive: false },
  ])
  assert.equal(tabs.find(0, FIVE_STRING), undefined)
})

test('batches string changes into one PATCH a second after the last', async () => {
  const tabs = new AlternateTabs('song', [saved({ strings: { 1: 2, 5: 3 } })])
  const tab = tabs.find(0, STANDARD)
  tabs.edit(tab, { 5: null, 7: 4 })
  mock.timers.tick(500)
  tabs.edit(tab, { 7: 3 })
  mock.timers.tick(999)
  assert.equal(requests.length, 0)
  mock.timers.tick(1)
  await settle()
  assert.deepEqual(tab.strings, { 1: 2, 7: 3 })
  assert.deepEqual(requests, [
    { method: 'PATCH', url: '/s/song/alt/tab-1', body: { strings: { 5: null, 7: 3 } }, keepalive: false },
  ])
})

test('retries failed saves with the next', async () => {
  const onError = mock.fn()
  const tabs = new AlternateTabs('song', [saved()], { onError })
  const tab = tabs.find(0, STANDARD)
  failing = true
  tabs.edit(tab, { 2: 1 })
  const added = tabs.add(0, FIVE_STRING, 10, { 3: 2 })
  await tabs.flush()
  await settle()
  assert.equal(onError.mock.callCount(), 2)
  assert.equal(added.id, null)

  failing = false
  tabs.edit(tab, { 4: 3 })
  await tabs.flush({ keepalive: true })
  await settle()
  assert.deepEqual(requests.slice(-2).map(({ method, body, keepalive }) => [method, body.strings, keepalive]), [
    ['POST', { 3: 2 }, true],
    ['PATCH', { 2: 1, 4: 3 }, true],
  ])
})

test('retries a failed replacement with the next save', async () => {
  const tabs = new AlternateTabs('song', [saved({ strings: { 1: 2 } })])
  const tab = tabs.find(0, STANDARD)
  failing = true
  tabs.replace(tab, { 4: 1 }, 'beam')
  await settle()

  failing = false
  tabs.edit(tab, { 5: 2 })
  await tabs.flush()
  await settle()
  assert.deepEqual(requests.slice(1).map(({ method, body }) => [method, body]), [
    ['PUT', { strings: { 4: 1, 5: 2 }, optimizer: 'beam' }],
  ])
  await tabs.flush()
  assert.equal(requests.length, 2)
})

test('saves changes made while a new tab is being saved', async () => {
  const tabs = new AlternateTabs('song')
  const tab = tabs.add(0, STANDARD, 10, { 1: 2 })
  tabs.edit(tab, { 2: 3 })  // before the POST answers
  await settle()
  await settle()
  assert.deepEqual(requests.map(({ method, body }) => [method, body.strings]), [['POST', { 1: 2 }], ['PATCH', { 2: 3 }]])
})
