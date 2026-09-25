# frozen_string_literal: true

require 'rails_helper'
require 'alpha_tab'
require 'songsterr'

RSpec.describe AlphaTab do
  let(:alpha_tab) { described_class.new }
  let(:page) { Songsterr::Page.new(file_fixture('songsterr/page.html').read) }
  let(:parts) { (0..2).map { JSON.parse(Zlib.gunzip(file_fixture("songsterr/#{it}.json.gz").binread)) } }

  describe '#songsterr_to_gp' do
    it "converts Songsterr tracks into a Guitar Pro 7 score" do
      result = alpha_tab.songsterr_to_gp(page.metadata, parts)

      Tempfile.create(['score', '.gp'], binmode: true) do |file|
        file.write(result['gp'].unpack1('m'))
        file.flush
        info = alpha_tab.score_info(file.path)
        expect(info).to include('title' => "W.M.A.", 'artist' => "Pearl Jam", 'tempo' => 108)
        expect(info['tracks'].pluck('name')).to eq ["Distortion Guitar", "Electric Bass (finger)", "Drums"]
      end
      expect(result['playedBars']).to have(150).items
      expect(result['playedBars'].first(2)).to eq [[0, 0], [1, 0]]
      expect(result['warnings']).to eq []
    end

    it "expands repeats and alternate endings into played bars" do
      repeats = JSON.parse(file_fixture('songsterr/repeats.json').read)
      result = alpha_tab.songsterr_to_gp(page.metadata, [repeats])
      expect(result['playedBars']).to eq [[0, 0], [1, 0], [2, 0], [3, 0], [1, 1], [2, 1], [4, 0], [5, 0]]
    end

    it "reports Songsterr keys it doesn't map" do
      part = parts[1].deep_dup
      part['measures'][0]['voices'][0]['beats'][0]['notes'][0]['harmonic'] = 'natural'
      expect(alpha_tab.songsterr_to_gp(page.metadata, [part])['warnings']).to eq ["note.harmonic (1×)"]
    end
  end
end
