# frozen_string_literal: true

class User < ApplicationRecord
  include AuthenticationModel

  # Instrument types a user can play (other covers sound effects and the like)
  INSTRUMENT_TYPES = (Song::INSTRUMENT_TYPES - %i[other]).freeze

  # The instrument types the user plays (a plain array, since a torque-postgresql EnumSet raises on invalid values)
  attribute :instrument_types, :string, array: true, default: ->{ [] }

  validates :instrument_types, instrument_types: { except: Song::INSTRUMENT_TYPES - INSTRUMENT_TYPES }

  has_many :playlists, dependent: nil
  has_many :play_histories, dependent: nil
  has_many :song_notes, dependent: nil
  has_many :alternate_tabs, dependent: nil
end
