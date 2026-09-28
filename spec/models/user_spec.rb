# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User do
  it "stores the instrument types the user plays, which can't include other" do
    user = create(:user, instrument_types: %i[bass keys])
    expect(user.reload.instrument_types).to eq %w[bass keys]
    expect(User.new.instrument_types).to eq []

    user.instrument_types = %w[bass other bogus]
    expect(user).not_to be_valid
    expect(user.errors[:instrument_types]).to eq ["is not included in the list"]
  end
end
