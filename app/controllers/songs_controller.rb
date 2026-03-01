class SongsController < ApplicationController
  before_action :find_song, except: %i[index new create]

  def index
    @songs ||= Song.all.order_by(:artist, :title)
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
    @song.jellyfin_id ||= @song.find_jellyfin.first&.id

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
      if @song.title_changed? || @song.artist_changed?
        @song.jellyfin_id = @song.find_jellyfin.first&.id
      end

      if @song.save
        format.html { redirect_to @song, notice: "Song was successfully updated.", status: :see_other }
        format.json { render :player, status: :ok, location: @song }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @song.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @song.destroy
    respond_to do |format|
      format.html { redirect_to songs_path, notice: "Song was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def player
    @playlists = Current.user.playlists.order_by(:name)
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
      song_id = @song.id
      playlist = Playlist.find(params[:playlist])
      playlist.queue_atomic do
        if params[:checked]
          playlist.songs << song_id
        else
          playlist.songs -= [song_id]
        end
      end
      playlist.save!
    end

    playlists = Current.user.playlists.order_by(:name)
    render partial: 'songs/playlist_menu', locals: { song: @song, playlists: }
  end

  def track_history
    date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    duration = params[:duration].to_f

    history = PlayHistory.where(user: Current.user, song: @song, date:).first || PlayHistory.new(user: Current.user, song: @song, date:)
    history.queue_atomic { history.duration += duration }
    history.save!
    head :ok
  end

private

  def find_song
    @song = Song.find_by_slug_or_id!(params[:id])
  end

  def song_params
    sync_points = JSON.parse(params[:song][:sync_points].presence || '[]')
    params.require(:song)
      .permit(:title, :artist, :sync_points, :cover, :cover_data,
        score: {}, audio: {},
        instruments: []
      )
      .with_defaults(instruments: %w[bass])
      .merge(sync_points:)
  end
end
