# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Songsterr do
  describe '.get' do
    let(:url) { 'https://www.songsterr.com/api/example' }

    it "gives up on unresponsive servers" do
      expect(described_class.http.options).to have_attributes(open_timeout: Songsterr::OPEN_TIMEOUT, timeout: Songsterr::TIMEOUT)
    end

    it "raises on timeouts" do
      stub_request(:get, url).to_timeout
      expect { described_class.get(url) }.to raise_error(Songsterr::Error, /Failed to fetch #{url}/)
    end

    it "follows redirects, e.g. from a non-canonical page slug" do
      canonical = 'https://www.songsterr.com/a/wsa/canonical-tab-s1'
      stub_request(:get, url).to_return(status: 301, headers: { 'Location' => canonical })
      stub_request(:get, canonical).to_return(body: 'page')
      expect(described_class.get(url)).to eq 'page'
    end
  end
end
