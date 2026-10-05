# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SongsController, vcr: { cassette_name: 'Jellyfin' }  do
  let(:user) { create(:user) }
  let(:song) { create(:song) }
  before { sign_in user }

  describe "#index" do
    before do
      create(:song, title: "Schism", artist: "Tool", track_types: %w[bass])
      create(:song, title: "Hysteria", artist: "Muse", track_types: %w[bass])
    end

    def titles = Nokogiri::HTML(response.body).css('.song .card-title').map(&:text)

    it "shows songs matching the search" do
      get :index, params: { q: 'tool' }
      expect(response).to be_successful
      expect(titles).to eq ["Schism"]
      expect(response.body).to include 'value="tool"'
      # Enter submits with the form's first button, which searches Songsterr instead
      submit = Nokogiri::HTML(response.body).at_css('form[role=search] [type=submit]')
      expect(submit['formaction']).to eq songsterr_search_songs_path
    end

    it "renders just the page for the search box's Turbo Frame updates" do
      request.headers['Turbo-Frame'] = 'songs'
      get :index, params: { q: 'muse' }
      expect(titles).to eq ["Hysteria"]
      expect(Nokogiri::HTML(response.body).at_css('.song-count').text).to eq "1 song"
      expect(response.body).to include '<turbo-frame id="songs" target="_top">'
      expect(response.body).not_to include 'navbar' # turbo-rails' minimal frame layout, not the application layout
    end

    it "has a menu on each song for adding it to the user's playlists" do
      hysteria, schism = Song.find_by(title: "Hysteria"), Song.find_by(title: "Schism")
      practice = create(:playlist, name: "Practice", user:, songs: [schism])
      create(:playlist, name: "Other user's", user: create(:user))
      get :index

      # listed by title, with checkbox IDs unique to each song's menu
      checkboxes = Nokogiri::HTML(response.body).css('.song .dropdown-menu input[type=checkbox]')
      expect(checkboxes.map { it.next_element.text }).to eq ["Practice", "Practice"]
      expect(checkboxes.map { it['checked'] }).to eq [nil, 'checked']
      expect(checkboxes.map { it['id'] }).to eq ["playlist_#{hysteria.id}_#{practice.id}", "playlist_#{schism.id}_#{practice.id}"]
      # in the success color for songs already in a playlist
      # in the success color for songs already in a playlist, and with each icon and menu marked with its song, for updating its
      # other copies on the page
      icons = Nokogiri::HTML(response.body).css('.song .playlist-icon')
      expect(icons.map { it['class'].split.include?('text-success') }).to eq [false, true]
      expect(icons.map { it['data-song'] }).to eq [hysteria.id, schism.id]
      forms = Nokogiri::HTML(response.body).css('.song .dropdown-menu form')
      expect(forms.map { it['data-playlist-menu-song-value'] }).to eq [hysteria.id, schism.id]
    end

    it "sorts the songs, keeping the selected sort" do
      Song.find_by(title: "Schism").update!(created_at: 1.hour.from_now)
      get :index, params: { sort: 'newest' }
      expect(titles).to eq ["Schism", "Hysteria"]
      expect(Nokogiri::HTML(response.body).at_css('select[name=sort] option[selected]')['value']).to eq 'newest'

      get :index
      expect(titles).to eq ["Hysteria", "Schism"]
      expect(Nokogiri::HTML(response.body).at_css('.song-count').text).to eq "2 songs"
      expect(Nokogiri::HTML(response.body).at_css('select[name=sort] option[selected]')).to be_nil
    end

    it "says when nothing matches" do
      get :index, params: { q: 'nothing' }
      expect(response.body).to include "No songs match"
    end

    it "offers a Songsterr search for any search, with or without local results" do
      get :index, params: { q: 'nothing' }
      button = Nokogiri::HTML(response.body).at_css('a.songsterr-search')
      expect(button['href']).to eq '/s/songsterr_search?q=nothing'
      expect(button['data-turbo-frame']).to eq 'songs'

      get :index, params: { q: 'tool' }
      expect(titles).to be_present
      expect(Nokogiri::HTML(response.body).at_css('a.songsterr-search')['href']).to eq '/s/songsterr_search?q=tool'
      get :index
      expect(response.body).not_to include 'songsterr-search'
    end
  end

  describe "#songsterr_search" do
    let(:results) do
      JSON.parse(file_fixture('songsterr/search.json').read).reject { it['isJunk'] }.map do
        Songsterr::Result.new(song_id: it['songId'], artist: it['artist'], title: it['title'], tracks: it['tracks'])
      end
    end

    it "shows Songsterr matches as cards, linking already-imported songs" do
      imported = create(:song, title: "Head Over Heels", artist: "Accept", songsterr_song: build(:songsterr_song, id: 1041, song: nil))
      user.update!(instrument_types: %w[guitar bass])
      allow(Songsterr::Search).to receive(:call).with("head over heels").and_return(results)
      get :songsterr_search, params: { q: "head over heels" }

      doc = Nokogiri::HTML(response.body)
      cards = doc.css('turbo-frame .songsterr.card')
      expect(cards.map { it.at_css('.card-title').text }).to eq ["Head Over Heels", "Head Over Heels"]
      expect(cards.first.css('.badge.text-bg-secondary').map(&:text)).to eq %w[drums bass guitar keys vocals]

      tff = doc.at_css('turbo-frame#songsterr_20361')
      expect(tff.at_css('a[target=_blank][rel=noopener]')['href'])
        .to eq 'https://www.songsterr.com/a/wsa/tears-for-fears-head-over-heels-tab-s20361t1' # the user's main instrument, guitar
      expect(tff.at_css('form[action="/s/songsterr_import"] button').text).to include "Import"
      expect(tff.at_css('input[name=song_id]')['value']).to eq '20361'
      expect(tff.css('input[name="track_types[]"]').map { it['value'] }).to eq %w[vocals guitar bass keys drums]

      accept = doc.at_css('turbo-frame#songsterr_1041')
      expect(accept.at_css('form[action="/s/songsterr_import"]')).to be_nil
      expect(accept.at_css("a[href='#{player_path(imported)}']")).to be_present
      expect(accept.at_css(".dropdown-menu form[action='#{playlist_song_path(imported)}']")).to be_present
    end

    it "links songs already in the library by title and artist, since importing would replace them" do
      manual = create(:song, title: "HEAD OVER HEELS", artist: "tears for fears")
      allow(Songsterr::Search).to receive(:call).and_return(results)
      get :songsterr_search, params: { q: "head over heels" }

      tff = Nokogiri::HTML(response.body).at_css('turbo-frame#songsterr_20361')
      expect(tff.at_css('form[action="/s/songsterr_import"]')).to be_nil
      expect(tff.at_css("a[href='#{player_path(manual)}']")).to be_present
    end

    it "renders into the search results frame" do
      allow(Songsterr::Search).to receive(:call).and_return([])
      request.headers['Turbo-Frame'] = 'songs'
      get :songsterr_search, params: { q: "zzz" }
      expect(response.body).to include '<turbo-frame id="songs" target="_top">'
      expect(response.body).to include "No Songsterr matches for zzz"
    end

    it "shows Songsterr errors" do
      allow(Songsterr::Search).to receive(:call).and_raise(Songsterr::Error, "Failed to fetch")
      get :songsterr_search, params: { q: "x" }
      expect(response).to be_successful
      expect(Nokogiri::HTML(response.body).at_css('.alert-danger').text).to include "Can't search Songsterr: Failed to fetch"
    end

    it "goes back to the song search without a query" do
      get :songsterr_search
      expect(response).to redirect_to songs_path
    end
  end

  describe "#songsterr_import" do
    include ActiveJob::TestHelper
    include ActiveSupport::Testing::TimeHelpers

    let(:params) { { song_id: '20361', artist: "Tears for Fears", title: "Head Over Heels", track_types: %w[bass keys evil] } }
    let(:match) do
      Song::SongsterrMatch.new(song_id: 20361, artist: "Tears for Fears", title: "Head Over Heels", track_types: %w[bass keys other])
    end

    it "imports in the background, showing the card's progress" do
      freeze_time do
        expect { post :songsterr_import, params: }
          .to have_enqueued_job(SongsterrImportJob).with(user, match.to_h).at(SongsterrImportJob::START_DELAY.from_now)
      end

      frame = Nokogiri::HTML(response.body).at_css('turbo-frame#songsterr_20361')
      expect(frame.text).to include "Importing…"
      expect(frame.at_css('turbo-cable-stream-source')).to be_present
      expect(frame.at_css('ul#songsterr_20361_log')).to be_present
      expect(frame.at_css('form')).to be_nil
    end

    it "rejects invalid Songsterr ids" do
      expect { post :songsterr_import, params: params.merge(song_id: 'https://evil.example/') }.not_to have_enqueued_job
      expect(response).to have_http_status :bad_request
    end
  end

  it "#new" do
    get :new
    expect(response).to be_successful
  end

  it "#edit" do
    get :edit, params: { id: song }
    expect(response).to be_successful

    # parsed as a browser does, which merges a nested form's fields (like its `_method`) into the outer form
    doc = Nokogiri::HTML5(response.body)
    edit_form, delete_form = doc.at_css("form[action=\"#{song_path(song)}\"]:not(#delete_song)"), doc.at_css('form#delete_song')
    expect(edit_form.css('input[name=_method]').map { it['value'] }).to eq %w[patch]
    expect(delete_form.css('input[name=_method]').map { it['value'] }).to eq %w[delete]
    expect(doc.at_css('button[form=delete_song]').text.squish).to eq "Delete"
  end

  it "#create" do
    expect {
      attrs = attributes_for(:song).except(:jellyfin_id).as_json
      post :create, params: { song: attrs }
    }.to change(Song, :count).by(1)
    expect(response).to redirect_to song_path(assigns(:song))
  end

  describe "track types" do
    it "shows each track's instrument, noting overrides" do
      song.update!(track_types: %w[keys])
      get :edit, params: { id: song }
      row = Nokogiri::HTML(response.body).at_css('table[aria-labelledby="tracks-label"] tr')
      expect(row.at_css('td').text).to eq "Electric Bass"
      expect(row.at_css('select[name="song[track_types][]"] option[selected]')['value']).to eq 'keys'
      expect(row.text).to include "Detected as Bass"
    end

    it "saves overridden track types" do
      patch :update, params: { id: song, song: { title: song.title, track_types: %w[keys] } }
      expect(song.reload.track_types).to eq %w[keys]
    end

    it "saves an uploaded score" do
      score = Rack::Test::UploadedFile.new(file_fixture('Tears for Fears - Head Over Heels.gpx'), 'application/octet-stream')
      audio = Rack::Test::UploadedFile.new(file_fixture('empty.mp3'), 'audio/mpeg')
      expect {
        patch :update, params: { id: song, song: { score:, audio: } }
      }.to change { song.reload.score_data['id'] }.and change { song.reload.audio_data }.from(nil)
    end

    it "detects a new score's track types instead of the submitted ones" do
      song.update!(track_types: %w[keys])
      score = upload_fixture('Tears for Fears - Head Over Heels.gpx', 'audio/x-gtp').to_json
      patch :update, params: { id: song, song: { score:, track_types: %w[keys] } }
      expect(song.reload.track_types).to eq %w[bass]
    end
  end

  it "#update" do
    patch :update, params: { id: song, song: { title: "New title" } }
    expect(response).to have_http_status(:see_other)
    expect(song.reload.title).to eq "New title"
    expect(response).to redirect_to song_path(song.reload)
  end

  it "redirects pages for an old slug or ID to the song's current URL" do
    old_slug = song.slug
    song.update!(title: "Shout")

    get :player, params: { id: old_slug, track: '1' }
    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to player_url(song, track: '1')

    get :show, params: { id: song.id }
    expect(response).to redirect_to song_url(song)

    get :show, params: { id: song.slug }
    expect(response).to be_successful

    post :track_history, params: { id: old_slug, duration: 1 }
    expect(response).to be_successful
  end

  it "redisplays the edit form for the saved slug when changing the title fails" do
    patch :update, params: { id: song, song: { title: '', artist: "Sigur Rós" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Nokogiri::HTML(response.body).at_css("form[action=\"#{song_path(song)}\"]")).to be_present
  end

  it "returns to the page that linked to the edit page after saving, but only on this site" do
    request.env['HTTP_REFERER'] = player_url(song)
    get :edit, params: { id: song }
    expect(Nokogiri::HTML(response.body).at_css('input[name="return_to"]')['value']).to eq player_url(song)

    patch :update, params: { id: song, song: { title: "New title" }, return_to: player_url(song) }
    expect(response).to redirect_to player_url(song)

    patch :update, params: { id: song.reload, song: { title: "Newer title" }, return_to: 'https://evil.example/phish' }
    expect(response).to redirect_to song_path(song.reload)
  end

  describe "cover buttons" do
    let(:match) do
      CoverArt::Match.new(source: :deezer, artist: "Tears for Fears", title: "Shout", album: "Songs from the Big Chair",
                          image_url: 'https://cdn.example/big-chair.jpg')
    end
    def cover = Rack::Test::UploadedFile.new(file_fixture('cover.jpg'), 'image/jpeg')

    before { stub_request(:get, match.image_url).to_return(body: file_fixture('cover.jpg').binread) }

    it "finds a cover for the form's title and artist, redisplaying the form unsaved until it's saved" do
      allow(CoverArt).to receive(:search).with(artist: "Tears for Fears", title: "Shout").and_return(match)
      patch :find_cover, params: { id: song, song: { title: "Shout" } }

      expect(response).to have_http_status(:ok)
      expect(flash.now[:notice]).to eq "Found the cover of Songs from the Big Chair on Deezer.  Save to keep it."
      expect(response.body).to include 'value="Shout"'
      expect(song.reload).to have_attributes(title: "Head Over Heels", cover: nil)

      cover_data = Nokogiri::HTML(response.body).at_css('input[type=hidden][name="song[cover]"]')['value']
      patch :update, params: { id: song, song: { title: "Shout", cover: cover_data } }
      expect(song.reload.cover).to have_attributes(original_filename: "Tears for Fears - Songs from the Big Chair.jpg")
    end

    it "accepts the edit form's CSRF token from each of its buttons, which submit it to different actions" do
      ActionController::Base.allow_forgery_protection = true
      get :edit, params: { id: song }
      token = Nokogiri::HTML5(response.body).at_css("form[action=\"#{song_path(song)}\"] input[name=authenticity_token]")['value']
      allow(CoverArt).to receive(:search).and_return(nil)

      statuses = %i[find_cover remove_cover update].map do |action|
        patch action, params: { id: song, authenticity_token: token, song: { title: song.title } }
        response.status
      end
      expect(statuses).to eq [200, 200, 303]
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "says when no cover is found, or the search fails" do
      allow(CoverArt).to receive(:search).and_return(nil)
      patch :find_cover, params: { id: song, song: { title: song.title } }
      expect(flash.now[:error]).to eq "No cover art found for Tears for Fears - Head Over Heels."

      allow(CoverArt).to receive(:search).and_raise(CoverArt::Error, "Failed to fetch")
      patch :find_cover, params: { id: song, song: { title: song.title } }
      expect(flash.now[:error]).to eq "Can't search for cover art: Failed to fetch"
    end

    it "deletes the cover when the form is saved, unless it's replaced" do
      song.update!(cover:)
      get :edit, params: { id: song }
      expect(Nokogiri::HTML(response.body).css('button[formaction]').map(&:text).map(&:squish)).to eq ["Find Cover", "Delete Cover"]

      patch :remove_cover, params: { id: song, song: { title: song.title } }
      expect(Nokogiri::HTML(response.body).at_css('input[name="song[remove_cover]"]')['value']).to eq 'true'
      expect(response.body).not_to include 'Delete Cover'
      expect(song.reload.cover).to be_present

      patch :update, params: { id: song, song: { remove_cover: 'true', cover: } }
      expect(song.reload.cover).to be_present

      patch :update, params: { id: song, song: { remove_cover: 'true' } }
      expect(song.reload.cover).to be_nil
    end
  end

  it "#destroy" do
    song
    expect {
      delete :destroy, params: { id: song }
    }.to change(Song, :count).by(-1)
    expect(response).to have_http_status(:see_other)
  end

  describe "#player" do
    let(:song) { create(:song, track_types: %w[guitar bass drums]) }

    def player_song
      JSON.parse(Nokogiri::HTML(response.body).at_css('[data-controller="player"]')['data-player-song-value'])
    end

    it "shows the tracks of the user's instruments" do
      user.update!(instrument_types: %w[bass drums])
      get :player, params: { id: song }
      expect(response).to render_template(:player)
      expect(response).to be_successful
      expect(player_song).to include('trackTypes' => %w[guitar bass drums], 'tracks' => [1, 2])
    end

    it "includes the user's note" do
      create(:song_note, user:, song:, speed: 0.75, looping: true)
      create(:song_note, song:, speed: 0.5)
      get :player, params: { id: song }
      expect(player_song['note']).to include('speed' => 0.75, 'looping' => true)
    end

    it "includes the user's alternate tabs" do
      tab = create(:alternate_tab, user:, song:, strings: { '2' => 1 })
      create(:alternate_tab, song:)
      get :player, params: { id: song }
      expect(player_song['alternateTabs']).to eq [
        { 'id' => tab.id, 'trackIndex' => 0, 'tuning' => [43, 38, 33, 28], 'noteCount' => 477, 'strings' => { '2' => 1 },
          'optimizer' => nil },
      ]
    end

    it "shows the default track when the user's instruments aren't in the song" do
      user.update!(instrument_types: %w[keys])
      get :player, params: { id: song }
      expect(player_song).to include('tracks' => nil)
    end

    describe "skip buttons" do
      let(:songs) { %w[One Two Three].map { create(:song, title: it) } }
      let(:playlist) { create(:playlist, user:, name: "Practice", songs:) }

      def page = Nokogiri::HTML(response.body)
      def previous_url = page.at_css('[data-controller="player"]')['data-player-previous-url-value']
      def next_link = page.at_css('.at-skip-forward')

      it "skips to the previous and next songs in the playlist being played" do
        get :player, params: { playlist_id: playlist, id: songs.second }
        expect(response).to be_successful
        expect(previous_url).to eq '/p/practice/one-tears-for-fears'
        expect(next_link['href']).to eq '/p/practice/three-tears-for-fears'

        get :player, params: { playlist_id: playlist, id: songs.third }
        expect(previous_url).to eq '/p/practice/two-tears-for-fears'
        expect(next_link['href']).to be_nil
        expect(next_link['class']).to include 'unavailable'
      end

      it "only skips back to the start without a playlist, or a playlist without the song" do
        get :player, params: { id: songs.second }
        expect(previous_url).to be_nil
        expect(next_link['href']).to be_nil

        get :player, params: { playlist_id: create(:playlist, user:, songs: [songs.first]), id: songs.second }
        expect(response).to be_successful
        expect(previous_url).to be_nil
        expect(next_link['href']).to be_nil
      end

      it "redirects an old playlist slug or ID to its current URL" do
        old_slug = playlist.slug
        playlist.update!(name: "Warmups")
        get :player, params: { playlist_id: old_slug, id: songs.first, track: '1' }
        expect(response).to redirect_to '/p/warmups/one-tears-for-fears?track=1'
        expect(response).to have_http_status :moved_permanently

        get :player, params: { playlist_id: playlist.id, id: songs.first }
        expect(response).to redirect_to '/p/warmups/one-tears-for-fears'
      end

      it "only finds the user's playlists" do
        expect { get :player, params: { playlist_id: create(:playlist, user: create(:user), songs:), id: songs.first } }
          .to raise_error ActionController::RoutingError
      end
    end
  end

  it "#score" do
    get :score, params: { id: song }
    expect(response).to be_successful
  end

  it "#audio" do
    song = create(:song, :with_audio)
    get :audio, params: { id: song }
    expect(response).to be_successful
  end

  describe "#track_history" do
    let(:play_date) { '2026-01-15' }

    it "creates a new play history record" do
      expect {
        post :track_history, params: { id: song, date: play_date, duration: '120.5' }
        expect(response).to be_successful
      }.to change(PlayHistory, :count).by(1)
    end

    it "accumulates duration for existing record on same day" do
      create(:play_history, user:, song:, date: Date.parse(play_date), duration: 60.0)
      post :track_history, params: { id: song, date: play_date, duration: '30.0' }

      expect(response).to be_successful
      expect(PlayHistory.where(user:, song:, date: Date.parse(play_date)).first.duration).to be_within(0.01).of(90.0)
    end
  end
end
