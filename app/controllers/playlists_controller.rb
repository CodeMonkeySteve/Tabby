# frozen_string_literal: true

class PlaylistsController < ApplicationController
  before_action :find_playlist, only: %i[show edit update destroy]

  def show; end

  def new
    @playlist = Playlist.new
  end

  def edit; end

  def create
    @playlist = Playlist.new(playlist_params.merge(user: Current.user))
    if @playlist.save
      redirect_to @playlist, notice: "Playlist was successfully created"
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @playlist.update(playlist_params)
      redirect_to @playlist, notice: "Playlist was successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @playlist.destroy
    redirect_to playlists_path, notice: "Playlist was successfully destroyed", status: :see_other
  end

private

  # Finds the playlist by its current or an old slug, or its ID, redirecting pages to its current URL
  def find_playlist
    @playlist = Current.user.playlists.friendly.find(params.expect(:id))
    if request.get? && params[:id] != @playlist.to_param
      redirect_to url_for(id: @playlist, params: request.query_parameters), status: :moved_permanently
    end
  end

  def playlist_params
    params.expect(playlist: [:name])
  end
end
