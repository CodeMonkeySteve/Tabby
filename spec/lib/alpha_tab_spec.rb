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
          ...(() => {
            const bar = staff.bars[2];
            const [grace, accented, whammy, slide] = bar?.voices[0].beats ?? [];
            if (!bar) return {};
            return {
              grace: grace.graceType,
              accent: accented.notes[0].accentuated,
              leftHandVibrato: accented.notes[0].vibrato,
              text: accented.text,
              crescendo: accented.crescendo,
              whammy: [whammy.hasWhammyBar, whammy.minWhammyPoint?.value],
              slideIn: slide.notes[0].slideInType,
              barLineRight: bar.barLineRight,
            };
          })(),
          logLevel: alphaTab.Logger.logLevel,
        };
      }
    JS

    function :techniques, <<~JS
      async (base64) => {
        const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(Buffer.from(base64, 'base64'), new alphaTab.Settings());
        return score.tracks[0].staves[0].bars[0].voices[0].beats.map((beat) => ({
          slap: beat.slap, tap: beat.tap, brush: [beat.brushType, beat.brushDuration], pickStroke: beat.pickStroke,
          tremoloMarks: beat.tremoloPicking?.marks ?? null,
        }));
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
          { 'repeat' => 3, 'voices' => [{ 'beats' => [{ 'type' => 1, 'duration' => [1, 1], 'rest' => true, 'notes' => [{ 'rest' => true }] }] }] },
          { 'doubleBarline' => true, 'voices' => [{ 'beats' => [
            { 'type' => 64, 'duration' => [1, 64], 'graceNote' => 'onBeat', 'notes' => [{ 'fret' => 3, 'string' => 2 }] },
            beat.([{ 'fret' => 5, 'string' => 2, 'accentuated' => 2, 'leftHandVibrato' => 'wide' }],
                  'text' => { 'text' => "w/ flanger", 'width' => 60 }, 'gradualVelocity' => 'crescendo'),
            beat.([{ 'fret' => 5, 'string' => 2 }],
                  'tremoloBar' => { 'tone' => 0, 'points' => [{ 'position' => 0, 'tone' => 0 }, { 'position' => 60, 'tone' => -50 }] }),
            beat.([{ 'fret' => 5, 'string' => 2, 'slide' => 'below' }]),
            beat.([{ 'fret' => 5, 'string' => 2 }])
          ] }] },
          { 'voices' => [{ 'beats' => [{ 'type' => 1, 'duration' => [1, 1], 'rest' => true, 'notes' => [{ 'rest' => true }] }] }] }
        ]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Effects", 'tracks' => [{ 'title' => "Guitar" }] }, [part])
      # AlphaTab enum values
      model = { triplet16th: 1, artificial: 2, slight: 1, wide: 2, on_beat: 1, heavy: 2, crescendo: 1, from_below: 1, light_light: 7,
                error: 4 }

      expect(result['warnings']).to eq []
      expect(AlphaTabInspector.new.effects(result['gp'])).to eq(
        'tripletFeels' => [model[:triplet16th]] * 4, 'repeatCounts' => [0, 3, 0, 0],
        'ghost' => true, 'letRing' => true, 'harmonic' => [model[:artificial], 12],
        'noteVibrato' => model[:slight], 'beatVibrato' => [0, model[:wide]], 'chord' => "Asus2",
        'grace' => model[:on_beat], 'accent' => model[:heavy], 'leftHandVibrato' => model[:wide], 'text' => "w/ flanger",
        'crescendo' => model[:crescendo], 'whammy' => [true, -2], 'slideIn' => model[:from_below], 'barLineRight' => model[:light_light],
        'logLevel' => model[:error],
      )
    end

    it "converts dead notes that have no fret" do
      dead_notes = [0, 1, 2].map { { 'string' => it, 'dead' => true } }
      part = {
        'instrumentId' => 30, 'strings' => 6, 'tuning' => [64, 59, 55, 50, 45, 40],
        'measures' => [{ 'signature' => [4, 4], 'voices' => [{ 'beats' => [{ 'type' => 1, 'duration' => [1, 1], 'notes' => dead_notes }] }] }]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Dead notes", 'tracks' => [{ 'title' => "Guitar" }] }, [part])
      expect(result['gp']).to be_present
      expect(result['warnings']).to eq []
    end

    it "maps Songsterr picking techniques" do
      beat = ->(**options) { { 'type' => 4, 'duration' => [1, 4], 'notes' => [{ 'fret' => 5, 'string' => 2 }], **options } }
      part = {
        'instrumentId' => 36, 'strings' => 4, 'tuning' => [43, 38, 33, 28],
        'measures' => [{ 'signature' => [4, 4], 'voices' => [{ 'beats' => [
          beat.('slapping' => true),
          beat.('brushStroke' => { 'direction' => 'down', 'duration' => 30, 'shift' => 100 }, 'upStroke' => 1),
          beat.('brushStroke' => { 'direction' => 'up', 'duration' => 60, 'shift' => 100 }, 'downStroke' => 1),
          beat.('tremolo' => [1, 32], 'tapping' => true)
        ] }] }]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Techniques", 'tracks' => [{ 'title' => "Bass" }] }, [part])
      none = { 'slap' => false, 'tap' => false, 'brush' => [0, 0], 'pickStroke' => 0, 'tremoloMarks' => nil }

      expect(result['warnings']).to eq []
      expect(AlphaTabInspector.new.techniques(result['gp'])).to eq [
        none.merge('slap' => true),
        none.merge('brush' => [2, 30], 'pickStroke' => 1), # BrushDown, PickStroke.Up
        none.merge('brush' => [1, 60], 'pickStroke' => 2), # BrushUp, PickStroke.Down
        none.merge('tremoloMarks' => 3, 'tap' => true)
      ]
    end

    it "reports Songsterr keys it doesn't map" do
      part = parts[1].deep_dup
      part['measures'][0]['voices'][0]['beats'][0]['notes'][0]['unknownEffect'] = true
      expect(alpha_tab.songsterr_to_gp(page.metadata, [part])['warnings']).to eq ["note.unknownEffect (1×)"]
    end
  end
end
