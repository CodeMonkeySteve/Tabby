pin 'application', preload: true

# Served from lib/alpha_tab/node_modules (see public/alphatab symlink) so its worker, worklet, and fonts load same-origin
pin '@coderline/alphatab', to: '/alphatab/alphaTab.min.mjs'

pin '@tonaljs/note', to: '@tonaljs--note.js' # @4.12.1
pin '@tonaljs/scale', to: '@tonaljs--scale.js' # @4.13.4
pin '@tonaljs/chord-type', to: '@tonaljs--chord-type.js' # @5.1.1
pin '@tonaljs/collection', to: '@tonaljs--collection.js' # @4.9.0
pin '@tonaljs/midi', to: '@tonaljs--midi.js' # @4.10.2
pin '@tonaljs/pcset', to: '@tonaljs--pcset.js' # @4.10.1
pin '@tonaljs/pitch', to: '@tonaljs--pitch.js' # @5.0.2
pin '@tonaljs/pitch-distance', to: '@tonaljs--pitch-distance.js' # @5.0.5
pin '@tonaljs/pitch-interval', to: '@tonaljs--pitch-interval.js' # @6.1.0
pin '@tonaljs/pitch-note', to: '@tonaljs--pitch-note.js' # @6.1.0
pin '@tonaljs/scale-type', to: '@tonaljs--scale-type.js' # @4.9.2

pin 'popper', to: 'popper.js', preload: true
pin 'bootstrap', to: 'bootstrap.min.js', preload: true

pin '@hotwired/turbo-rails', to: 'turbo.min.js', preload: true
pin '@hotwired/stimulus', to: 'stimulus.min.js', preload: true
pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js', preload: true
pin 'sortablejs' # @1.15.7

pin_all_from 'app/javascript/controllers', under: 'controllers'
pin_all_from 'app/javascript/lib', under: 'lib'
