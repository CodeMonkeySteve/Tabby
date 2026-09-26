# frozen_string_literal: true

require 'rails_helper'
require 'alpha_tab'
require 'songsterr'

RSpec.describe AlphaTab do
  # Reads back the effects the converter maps, from an exported Guitar Pro file
  class AlphaTabInspector < AlphaTab
    function :effects, <<~JS
      async (base64) => {
        const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(Buffer.from(base64, 'base64'), new alphaTab.Settings());
        const staff = score.tracks[0].staves[0];
        const beats = staff.bars.flatMap((bar) => bar.voices[0].beats);
        const note = (index) => beats[index].notes[0];
        return {
          tripletFeels: score.masterBars.map((bar) => bar.tripletFeel),
          repeatCounts: score.masterBars.map((bar) => bar.repeatCount),
          ghost: note(0).isGhost,
          letRing: note(0).isLetRing,
          harmonic: [note(1).harmonicType, note(1).harmonicValue],
          noteVibrato: note(2).vibrato,
          beatVibrato: [beats[2].vibrato, beats[3].vibrato],
          chord: staff.chords?.get(beats[0].chordId)?.name ?? null,
        };
      }
    JS
  end

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

    it "maps Songsterr notation effects" do
      beat = ->(notes, **options) { { 'type' => 4, 'duration' => [1, 4], 'notes' => notes, **options } }
      part = {
        'instrumentId' => 27, 'strings' => 6, 'tuning' => [64, 59, 55, 50, 45, 40],
        'measures' => [
          { 'signature' => [4, 4], 'tripletFeel' => '16th', 'voices' => [{ 'beats' => [
            beat.([{ 'fret' => 5, 'string' => 2, 'ghost' => true }], 'letRing' => true, 'chord' => { 'text' => "Asus2", 'width' => 39 }),
            beat.([{ 'fret' => 5, 'string' => 2, 'harmonic' => 'artificial', 'harmonicFret' => 12 }]),
            beat.([{ 'fret' => 5, 'string' => 2 }], 'vibrato' => true),
            beat.([{ 'fret' => 5, 'string' => 2 }], 'vibratoWithTremoloBar' => 'wide')
          ] }] },
          { 'repeat' => 3, 'voices' => [{ 'beats' => [{ 'type' => 1, 'duration' => [1, 1], 'rest' => true, 'notes' => [{ 'rest' => true }] }] }] }
        ]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Effects", 'tracks' => [{ 'title' => "Guitar" }] }, [part])
      model = { triplet16th: 1, artificial: 2, slight: 1, wide: 2 } # AlphaTab enum values

      expect(result['warnings']).to eq []
      expect(AlphaTabInspector.new.effects(result['gp'])).to eq(
        'tripletFeels' => [model[:triplet16th], model[:triplet16th]], 'repeatCounts' => [0, 3],
        'ghost' => true, 'letRing' => true, 'harmonic' => [model[:artificial], 12],
        'noteVibrato' => model[:slight], 'beatVibrato' => [0, model[:wide]], 'chord' => "Asus2",
      )
    end

    it "reports Songsterr keys it doesn't map" do
      part = parts[1].deep_dup
      part['measures'][0]['voices'][0]['beats'][0]['notes'][0]['unknownEffect'] = true
      expect(alpha_tab.songsterr_to_gp(page.metadata, [part])['warnings']).to eq ["note.unknownEffect (1×)"]
    end
  end
end
