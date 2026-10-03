require 'songsterr'

class SongsController < ApplicationController
  before_action :find_song, except: %i[index new create songsterr_search songsterr_import]

  def index
    @songs = Song.search(params[:q]).sorted(params[:sort], user: Current.user)
    @playlists = Current.user.playlists.order(:name)
  end

  # Songsterr songs matching the search, for importing
  def songsterr_search
    params[:q].present? or return redirect_to songs_path

    @matches = Songsterr::Search.call(params[:q]).map { Song::SongsterrMatch.from_result(it) }
    @imported = Song.for_songsterr_matches(@matches)
    @playlists = Current.user.playlists.order(:name)
  rescue Songsterr::Error => ex
    @error = "Can't search Songsterr: #{ex.message}"
  end

  # Starts importing a Songsterr song, showing its card's progress
  def songsterr_import
    match = Song::SongsterrMatch.new(
      song_id: Integer(params.require(:song_id), 10),
      artist: params[:artist].to_s,
      title: params.require(:title),
      # keeps each track's place, for the page URL's track index
      track_types: Array(params[:track_types]).map { Song::INSTRUMENT_TYPES.map(&:to_s).include?(it) ? it : 'other' },
    )
    SongsterrImportJob.set(wait: SongsterrImportJob::START_DELAY).perform_later(Current.user, match.to_h)
    render partial: 'songsterr_card', locals: { match:, state: :importing }
  rescue ArgumentError, ActionController::ParameterMissing
    head :bad_request
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

  # Finds the song by its current or an old slug, or its ID, redirecting pages to its current URL
  def find_song
    @song = Song.friendly.find(params[:id])
    if request.get? && params[:id] != @song.to_param
      redirect_to url_for(id: @song, params: request.query_parameters), status: :moved_permanently
    end
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
