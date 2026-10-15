# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlaylistsController do
  let(:user) { create(:user) }
  let(:songs) { create_list(:song, 3) }
  let(:playlist) { create(:playlist, user:, songs:) }

  before { sign_in user }

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
