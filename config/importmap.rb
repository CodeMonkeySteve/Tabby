pin 'application', preload: true

# pin '@coderline/alphatab', to: '@coderline--alphatab.js' # @1.8.0

# pin 'lodash', to: 'https://ga.jspm.io/npm:lodash@4.17.21/lodash.js'
pin 'jquery', preload: true, to: 'https://ga.jspm.io/npm:jquery@3.6.0/dist/jquery.min.js'

pin 'popper', to: 'popper.js', preload: true
pin 'bootstrap', to: 'bootstrap.min.js', preload: true

# pin "handlebars", to: 'https://ga.jspm.io/npm:handlebars@4.7.8/dist/handlebars.min.js'

#pin '@hotwired/turbo', to: 'turbo.min.js', preload: true
#pin '@hotwired/stimulus', to: 'stimulus.min.js', preload: true
#pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js', preload: true
#pin 'turbo_power' # @0.7.0

#pin 'stimulus-timeago', to: 'https://ga.jspm.io/npm:stimulus-timeago@4.0.0/dist/stimulus-timeago.es.js'

pin_all_from 'app/javascript/controllers', under: 'controllers'
pin_all_from 'app/javascript/lib', under: 'lib'
