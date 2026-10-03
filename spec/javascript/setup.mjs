// Resolves the importmap's bare specifiers (see config/importmap.rb) for Node, so `node --test` can load the app's modules
import { register } from 'node:module'

register('./resolve.mjs', import.meta.url)
