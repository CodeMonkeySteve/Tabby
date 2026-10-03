class PlaylistsController < ApplicationController
  def show
    @playlist = Current.user.playlists.find(params[:id])
  end

  def new
    @playlist = Playlist.new
  end

  def create
    @playlist = Playlist.new(playlist_params.merge(user: Current.user))
    if @playlist.save
      redirect_to @playlist, notice: "Playlist was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @playlist = Current.user.playlists.find(params[:id])
  end

  def update
    @playlist = Current.user.playlists.find(params[:id])
    if @playlist.update(playlist_params)
      redirect_to @playlist, notice: "Playlist was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @playlist = Current.user.playlists.find(params[:id])
    @playlist.destroy
    redirect_to playlists_path, notice: "Playlist was successfully destroyed.", status: :see_other
  end

private

  def playlist_params
    params.require(:playlist).permit(:name)
  end
end
