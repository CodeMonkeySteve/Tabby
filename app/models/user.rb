class User < ApplicationRecord
  include AuthenticationModel

  # The instrument types the user plays (a plain array, since a torque-postgresql EnumSet raises on invalid values)
  attribute :instrument_types, :string, array: true, default: []

  validates :instrument_types, instrument_types: { except: :other }

  has_many :playlists
  has_many :play_histories
end
