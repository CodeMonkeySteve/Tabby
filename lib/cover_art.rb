# frozen_string_literal: true

require 'faraday'

# Finds album cover art for a song in free online music catalogs (Deezer, then iTunes), neither of which needs an API key.  Their
# search results are ranked by popularity, so each catalog is searched by free text and its results are matched against the artist
# and title here, preferring studio albums over live recordings and compilations.
module CoverArt
  class Error < StandardError; end

  # A catalog track whose album has cover art
  Match = Data.define(:source, :artist, :title, :album, :image_url)

  # A downloaded cover image, named for Shrine
  class Image < StringIO
    attr_reader :original_filename

    def initialize(body, original_filename)
      super(body)
      @original_filename = original_filename
    end
  end

  USER_AGENT = 'Tabby'
  OPEN_TIMEOUT = 10 # seconds
  TIMEOUT = 30

  LIVE = /\blive\b/i
  COMPILATION = /\b(greatest|best of|hits|collection|anthology|essentials?|gold)\b/i

  # Trailing version notes on catalog titles, e.g. "Song (Remastered)", "Song [feat. Someone]", or "Song - 2011 Remaster"
  VERSION_SUFFIX = /\s*(\([^)]*\)|\[[^\]]*\]|\s-\s.*\b(remaster|live|version|mix|edit|mono|stereo|demo)\w*\b.*)\s*\z/i

  # The best match for the song's recording, or nil if no catalog has one.  Raises Error if a catalog can't be searched.
  def self.search(artist:, title:)
    key = [normalize(artist), normalize(title)]
    return if key.any?(&:empty?)

    sources.each do |source|
      matches = source.search("#{artist} #{title}").select { [normalize(it.artist), normalize(it.title)] == key }
      match = matches.min_by.with_index { |match, index| [penalty(match), index] }
      return match if match
    end
    nil
  end

  # Downloads a match's cover image.  Raises Error if it can't be.
  def self.download(match)
    Image.new(get(match.image_url), "#{match.artist} - #{match.album}#{File.extname(URI(match.image_url).path)}".tr('/', '-'))
  end

  def self.sources
    [Deezer, ITunes]
  end

  # Lowercase alphanumerics of a name, without accents, a leading "The", or trailing version notes, for comparing names
  def self.normalize(name)
    name = name.to_s
    name = name.sub(VERSION_SUFFIX, '') while name.match?(VERSION_SUFFIX)
    I18n.transliterate(name).downcase.sub(/\Athe\s+/, '').gsub('&', 'and').gsub(/[^a-z0-9]/, '')
  end

  # Lower for more likely original recordings: live recordings rank after compilations, which rank after studio albums
  def self.penalty(match)
    [match.title, match.album].any?(LIVE) ? 2 : match.album.match?(COMPILATION) ? 1 : 0
  end

  def self.get_json(url, params = {})
    JSON.parse(get(url, params))
  rescue JSON::ParserError => ex
    raise Error, "Invalid response from #{url}: #{ex.message}"
  end

  def self.get(url, params = {})
    http.get(url, params).body
  rescue Faraday::Error => ex
    raise Error, "Failed to fetch #{url}: #{ex.message}"
  end

  def self.http
    @http ||= Faraday.new(headers: { 'User-Agent' => USER_AGENT }, request: { open_timeout: OPEN_TIMEOUT, timeout: TIMEOUT }) do |faraday|
      faraday.response :raise_error
    end
  end
end

require 'cover_art/deezer'
require 'cover_art/i_tunes'
