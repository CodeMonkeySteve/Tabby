class SongsController < ApplicationController
  before_action :find_song, except: %i[index new create]

  def index
    @songs = Song.search(params[:q]).order(:title, :artist)
    @playlists = Current.user.playlists.order(:name)
  end

  def show
  end

  def new
    @song = Song.new
  end

  def edit
  end

  def create
    @song = Song.new(song_params)

    respond_to do |format|
      if @song.save
        format.html { redirect_to @song, notice: "Song was successfully created." }
        format.json { render :player, status: :created, location: @song }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @song.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      @song.assign_attributes(song_params)
      if @song.save
        format.html { redirect_to url_from(params[:return_to]) || @song, notice: "Song was successfully updated.", status: :see_other }
        format.json { render :player, status: :ok, location: @song }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @song.errors, status: :unprocessable_entity }
      end
    end
  end

  # Redisplays the edit form (unsaved, with its other changes) with cover art found for its title and artist
  def find_cover
    @song.assign_attributes(song_params)
    if (match = @song.fetch_cover_art)
      flash.now[:notice] = "Found the cover of #{match.album} on #{match.source.to_s.titleize}.  Save to keep it."
    else
      flash.now[:error] = "No cover art found for #{@song.artist} - #{@song.title}."
    end
    render :edit
  rescue CoverArt::Error => ex
    flash.now[:error] = "Can't search for cover art: #{ex.message}"
    render :edit
  end

  # Redisplays the edit form (unsaved, with its other changes) without its cover
  def remove_cover
    @song.assign_attributes(song_params.merge(remove_cover: true))
    flash.now[:notice] = "Save to delete the cover."
    render :edit
  end

  def destroy
    @song.destroy
    respond_to do |format|
      format.html { redirect_to songs_path, notice: "Song was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def player
    @playlists = Current.user.playlists.order(:name)
    render layout: false
  end

  def score
    send_data(@song.score.read, filename: @song.score.original_filename, content_type: @song.score.mime_type, disposition: 'inline')
  end

  def audio
    @song.audio or return head :not_found
    send_data(@song.audio.read, filename: @song.audio.original_filename, content_type: @song.audio.mime_type, disposition: 'inline')
  end

  def sync_points
    points = (params[:sync_points] || []).map do |sp|
      sp.permit(:barIndex, :barOccurence, :barPosition, :millisecondOffset).to_h
    end

    if @song.update(sync_points: points)
      head :ok
    else
      render json: @song.errors, status: :unprocessable_entity
    end
  end

  def playlist
    if params[:new_playlist_name].present?
      Playlist.create!(name: params[:new_playlist_name], user: Current.user, songs: [@song])
    else
      Current.user.playlists.find(params[:playlist]).include_song!(@song, params[:checked].to_bool)
    end

    playlists = Current.user.playlists.order(:name)
    render partial: 'songs/playlist_menu', locals: { song: @song, playlists: }
  end

  def track_history
    date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    duration = params[:duration].to_f

    PlayHistory.track!(user: Current.user, song: @song, date:, duration:)
    head :ok
  end

private

  def find_song
    @song = Song.find_by_slug_or_id!(params[:id])
  end

  def song_params
    sync_points = JSON.parse(params[:song][:sync_points].presence || '[]')
    params.require(:song)
      # files are uploads or cached file JSON from a form, or cached file hashes from JSON requests
      # remove_cover first, since attributes are assigned in this order, so a removed cover can be replaced
      .permit(:title, :artist, :sync_points, :remove_cover, :cover, :cover_data, :score, :audio, score: {}, audio: {}, track_types: [])
      .merge(sync_points:)
      .tap { it.delete(:track_types) if params[:song][:score].present? } # a new score's tracks are detected instead
  end
end
