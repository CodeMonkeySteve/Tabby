# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tabby is a Rails 8.1 music score library and player application. It manages songs with guitar/bass tablature (GPX/GTP files), synced audio playback, and cover art. Music scores are parsed via AlphaTab (a JavaScript library called from Ruby through the Nodo gem).

## Tech Stack

- **Ruby 3.4.8 / Rails 8.1** — no ActiveRecord; uses **NoBrainer** ORM with **RethinkDB**
- **Falcon** — async HTTP server (not Puma)
- **Shrine** — file uploads for scores, audio, and cover images
- **Hotwire** (Turbo + Stimulus) with **Importmap** (no JS bundler)
- **HAML** templates, **Bootstrap** CSS, **Simple Form**
- **OmniAuth** (Google OAuth2) for authentication, **CanCanCan** for authorization
- **AlphaTab** via **Nodo** — Node.js bridge for parsing music score files in `lib/alpha_tab/`

## Common Commands

```bash
bundle exec rails server     # Start the dev server

bundle exec rspec                                    # Run all tests
bundle exec rspec spec/models/song_spec.rb           # Run one spec file
bundle exec rspec spec/models/song_spec.rb:15        # Run spec at line

bin/rubocop                  # Lint (Omakase style)
bin/brakeman                 # Security static analysis
bin/bundler-audit            # Gem vulnerability scan
```

## Architecture

**Database**: RethinkDB (NoSQL). Models use `NoBrainer::Document` instead of ActiveRecord. There are no SQL migrations — NoBrainer handles schema sync. The `ApplicationRecord` base class includes `NoBrainer::Document`.

**Models**:
- `Song` — core entity with title, artist, instruments, tempo, score file (GPX/GTP), audio (MP3), cover image, and sync points (bar-to-millisecond mappings for playback sync)
- `User` / `Credential` — OAuth-based users with provider credentials
- `Current` — `ActiveSupport::CurrentAttributes` for request-scoped state

**Slug routing**: Songs use `Sluggable` concern for URL-friendly slugs derived from title + artist. Routes are mounted at `/s` (songs CRUD) and `/p/:id` (player view).

**File uploads**: Shrine with local filesystem storage (`storage/files/`). Three uploaders: `ApplicationUploader` (scores, audio), `ImageUploader` (covers with dimension/type validation). Score and audio files are served via dedicated controller actions.

**Score parsing**: `AlphaTab` class (in `lib/alpha_tab.rb`) uses Nodo to run Node.js and extract metadata (title, artist, tempo, tracks) from score files. Node modules live in `lib/alpha_tab/node_modules/`.

**Player**: The player view (`/p/:id`) renders with `layout: false` — it's a standalone HTML page for score playback with audio synchronization via sync points.

**Authentication**: OmniAuth Google OAuth2 flow. Session helpers in `Authentication` concern. `Current.user` holds the authenticated user per-request.

## Testing

RSpec with FactoryBot. No transactional fixtures (NoBrainer). Test helpers in `spec/support/`:
- `authentication.rb` — `sign_in` helper for controller specs
- `uploaded_file.rb` — `upload_fixture` for file upload tests
- `nobrainer.rb` — DB cleaning between tests

Fixtures (audio/score files) are in `spec/fixtures/`.

## Generators

Rails generators are configured for NoBrainer, HAML, RSpec, and FactoryBot (see `config/application.rb`).

## Player

The player page is implemented in `player.html.haml`, `player.js`, and `player.sass`.  It uses AlphaTab for score display and playback, with backing track audio.

## Style

* HAML element attributes should use `true` and `false` Ruby constants instead of "true" and "false" strings
* HAML attributes prefixed with "aria-" and "data-" should be in nested hashes without the prefix
* Ruby hash styles should apply to HAML attributes too  