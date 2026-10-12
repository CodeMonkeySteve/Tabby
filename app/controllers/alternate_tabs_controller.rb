# frozen_string_literal: true

# The current user's alternate tabs for a song (see AlternateTab)
class AlternateTabsController < ApplicationController
  before_action :find_tabs

  # Creates the tab for a track and tuning, or replaces the existing one
  def create
    attributes = params.expect(alternate_tab: [:track_index, :note_count, :optimizer, { tuning: [], strings: {} }])
    AlternateTab.tuning?(attributes[:tuning]) or return render json: { tuning: ["is invalid"] }, status: :unprocessable_content

    attempts = 0
    begin
      tab = @tabs.in_tuning(attributes[:tuning]).find_or_initialize_by(track_index: attributes[:track_index])
      saved = tab.update(attributes.with_defaults(strings: {}, optimizer: nil))
    rescue ActiveRecord::RecordNotUnique # created concurrently, so found the second time
      (attempts += 1) == 1 ? retry : raise
    end
    saved ? render(json: { id: tab.id }, status: :created) : render(json: tab.errors, status: :unprocessable_content)
  end

  # Merges string changes into the tab (PATCH), or replaces its strings (PUT)
  def update
    tab = @tabs.find(params.expect(:id))
    attributes = params.expect(alternate_tab: [:optimizer, { strings: {} }])
    saved = request.patch? ? tab.merge_strings(attributes[:strings].to_h) : tab.update(attributes)
    saved ? head(:no_content) : render(json: tab.errors, status: :unprocessable_content)
  end

  def destroy
    @tabs.find(params.expect(:id)).destroy!
    head :no_content
  end

private

  def find_tabs
    @tabs = Song.friendly.find(params.expect(:song_id)).alternate_tabs.where(user: Current.user)
  end
end
