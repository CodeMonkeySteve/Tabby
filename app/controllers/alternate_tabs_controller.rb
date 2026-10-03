# frozen_string_literal: true

# The current user's alternate tabs for a song (see AlternateTab)
class AlternateTabsController < ApplicationController
  before_action :find_tabs

  # Creates the tab for a track and tuning, or replaces the existing one
  def create
    attributes = params.require(:alternate_tab).permit(:track_index, :note_count, :optimizer, tuning: [], strings: {})
    # checked before finding the tab by it, since the database would round (or fail to cast) other values
    return render json: { tuning: ["is invalid"] }, status: :unprocessable_entity unless AlternateTab.tuning?(attributes[:tuning])

    attempts = 0
    begin
      tab = @tabs.in_tuning(attributes[:tuning]).find_or_initialize_by(track_index: attributes[:track_index])
      saved = tab.update(attributes.with_defaults(strings: {}, optimizer: nil))
    rescue ActiveRecord::RecordNotUnique # created concurrently, so found the second time
      (attempts += 1) == 1 ? retry : raise
    end
    saved ? render(json: { id: tab.id }, status: :created) : render(json: tab.errors, status: :unprocessable_entity)
  end

  # Merges string changes into the tab (PATCH), or replaces its strings (PUT)
  def update
    tab = @tabs.find(params[:id])
    attributes = params.require(:alternate_tab).permit(:optimizer, strings: {})
    saved = request.patch? ? tab.merge_strings(attributes[:strings].to_h) : tab.update(attributes)
    saved ? head(:no_content) : render(json: tab.errors, status: :unprocessable_entity)
  end

  def destroy
    @tabs.find(params[:id]).destroy!
    head :no_content
  end

private

  def find_tabs
    @tabs = Song.friendly.find(params[:song_id]).alternate_tabs.where(user: Current.user)
  end
end
