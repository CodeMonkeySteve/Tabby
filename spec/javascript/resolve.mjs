import { existsSync } from 'node:fs'
import { resolve as resolvePath } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = resolvePath(import.meta.dirname, '../..')

// The importmap's pins, mapped to the files Node loads (AlphaTab's unminified build, rather than the browser's minified one)
const PINS = {
  '@coderline/alphatab': 'lib/alpha_tab/node_modules/@coderline/alphatab/dist/alphaTab.mjs',
}

// A pin downloaded by `bin/importmap pin`, which names its file after the specifier
function vendored(specifier) {
  const path = `vendor/javascript/${specifier.replaceAll('/', '--')}.js`
  return existsSync(resolvePath(root, path)) ? path : null
}

export async function resolve(specifier, context, nextResolve) {
  const path = PINS[specifier] ?? (specifier.startsWith('lib/') ? `app/javascript/${specifier}.js` : vendored(specifier))
  if (!path) return nextResolve(specifier, context)
  return { url: pathToFileURL(resolvePath(root, path)).href, shortCircuit: true }
}
