class User < ApplicationRecord
  include AuthenticationModel

  # Instrument types a user can play (other covers sound effects and the like)
  INSTRUMENT_TYPES = (Song::INSTRUMENT_TYPES - %i[other]).freeze

  # The instrument types the user plays (a plain array, since a torque-postgresql EnumSet raises on invalid values)
  attribute :instrument_types, :string, array: true, default: []

  validates :instrument_types, instrument_types: { except: Song::INSTRUMENT_TYPES - INSTRUMENT_TYPES }

  has_many :playlists
  has_many :play_histories
  has_many :song_notes
  has_many :alternate_tabs
end
