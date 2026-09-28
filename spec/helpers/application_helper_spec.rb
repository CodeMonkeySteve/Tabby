# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper do
  it "#practice_time" do
    expect([45, 12 * 60 + 30, 65 * 60].map { helper.practice_time(it) }).to eq ["45s", "12m", "1h 5m"]
  end

  it "#relative_date" do
    today = Date.new(2026, 9, 30)
    expect([0, 1, 3, 10].map { helper.relative_date(today - it, today:) }).to eq ["Today", "Yesterday", "3 days ago", "Sep 20"]
  end
end
