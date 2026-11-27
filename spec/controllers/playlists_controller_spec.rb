# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlaylistsController do
  let(:user) { create(:user) }
  let(:songs) { create_list(:song, 3) }
  let(:playlist) { create(:playlist, user:, songs:) }

  before { sign_in user }

  describe "#index" do
    render_views

    it "lists the user's playlists by name" do
      create(:playlist, user:, name: "Warmups", songs:)
      create(:playlist, user:, name: "Ballads")
      create(:playlist, user: create(:user), name: "Theirs")

      get :index
      expect(response).to be_successful

      items = response.parsed_body.css('.playlists .list-group-item')
      expect(items.map { it.at_css('span').text }).to eq %w[Ballads Warmups]
      expect(items.map { it.at_css('.badge').text }).to eq %w[0 3]
      expect(items.first['href']).to eq playlist_path(Playlist.find_by(name: "Ballads"))
    end

    it "says when there are no playlists" do
      get :index
      expect(response.body).to include "No playlists yet"
    end
  end

  describe "#show" do
    render_views

    it "shows the playlist's name, its songs in order to drag, and a delete button with confirmation" do
      playlist.reorder_songs!(songs.reverse.map(&:id))

      get :show, params: { id: playlist }
      expect(response).to be_successful

      page = response.parsed_body
      name = page.at_css('form.inline-edit[data-controller="inline-edit"] input[name="playlist[name]"]')
      expect(name['value']).to eq playlist.name
      expect(name['data-inline-edit-target']).to eq 'input'
      expect(page.at_css('[data-controller="playlist-order"]')['data-playlist-order-url-value']).to eq order_playlist_path(playlist)
      expect(page.css('[data-song-id]').pluck('data-song-id')).to eq songs.reverse.map(&:id)
      expect(page.at_css('[data-song-id] .drag-handle + a')['href']).to eq playlist_player_path(playlist, songs.last)
      delete_form = page.at_css('form[data-turbo-confirm]:has(input[name="_method"][value="delete"])')
      expect(delete_form['action']).to eq playlist_path(playlist)
      expect(delete_form['data-turbo-confirm']).to eq "Delete #{playlist.name}?"
    end

    it "redirects an old slug to the current one" do
      old_slug = playlist.to_param
      playlist.update!(name: "Renamed")

      get :show, params: { id: old_slug }
      expect(response).to redirect_to playlist_path(playlist)
      expect(response).to have_http_status :moved_permanently
    end
  end

  describe "#update" do
    render_views

    it "renames the playlist, redirecting to its new URL" do
      patch :update, params: { id: playlist, playlist: { name: "Warmups" } }

      expect(playlist.reload.name).to eq "Warmups"
      expect(response).to redirect_to playlist_path(playlist)
      expect(response).to have_http_status :see_other
    end

    it "shows errors for an invalid name" do
      patch :update, params: { id: playlist, playlist: { name: " " } }

      expect(response).to have_http_status :unprocessable_content
      expect(response.parsed_body.at_css('.alert-danger').text).to include "Name can't be blank"
      expect(response.parsed_body.at_css('title').text).to eq playlist.name
      expect(playlist.reload.name).to eq "MyString"
    end
  end

  describe "#destroy" do
    it "deletes the playlist" do
      delete :destroy, params: { id: playlist }

      expect(Playlist.exists?(playlist.id)).to be false
      expect(response).to redirect_to playlists_path
    end

    it "doesn't delete another user's playlist" do
      other = create(:playlist, user: create(:user))

      expect { delete :destroy, params: { id: other } }.to raise_error ActionController::RoutingError
      expect(Playlist.exists?(other.id)).to be true
    end
  end

  describe "#order" do
    it "reorders the playlist's songs" do
      patch :order, params: { id: playlist, song_ids: songs.reverse.map(&:id) }, as: :json

      expect(response).to have_http_status :no_content
      expect(playlist.reload.song_ids).to eq songs.reverse.map(&:id)
    end

    it "doesn't reorder another user's playlist" do
      other = create(:playlist, user: create(:user), songs:)

      expect { patch :order, params: { id: other, song_ids: songs.reverse.map(&:id) }, as: :json }
        .to raise_error ActionController::RoutingError
      expect(other.reload.song_ids).to eq songs.map(&:id)
    end
  end
end
