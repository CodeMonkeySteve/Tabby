# Tabby

Tabby is a Rails 8.1 music score library and player application. It manages songs with guitar/bass tablature (GPX/GTP files), synced audio playback, and 
cover art. Music scores are parsed via AlphaTab (a JavaScript library called from Ruby through the Nodo gem).

## Tech Stack

- **Ruby / Rails 8.1** — **ActiveRecord** with **PostgreSQL**
- **Falcon** — async HTTP server (not Puma)
- **Shrine** — file uploads for scores, audio, and cover images
- **Hotwire** (Turbo + Stimulus) with **Importmap** (no JS bundler)
- **HAML** templates, **Bootstrap** CSS
- **OmniAuth** (Google OAuth2) for authentication, **CanCanCan** for authorization
- **AlphaTab** via **Nodo** — Node.js bridge for parsing music score files in `lib/alpha_tab/`

## Architecture

**Database**: PostgreSQL via ActiveRecord. `bin/rails rethinkdb:import` copies data from the legacy RethinkDB database into an empty PostgreSQL database.

**Authentication**: OmniAuth Google OAuth2 flow. Session helpers in `Authentication` concern. `Current.user` holds the authenticated user per-request.

## Feature Roadmap

* Play time tacking - measure the amount of time spent playing each song, post time to server, store per-user/-song/-day metrics.  Display as calendar, similar to GitHub contributions.

* Multiuser synchronization - users can form groups such that the play state and position is broadcast to all users so they can play along to the same song.

## Style

* HAML element attributes should use Ruby numeric and boolean literals instead of strings
* HAML attributes prefixed with "aria-" and "data-" should be in nested hashes without the prefix
* Ruby hash styles should apply to HAML attributes too
