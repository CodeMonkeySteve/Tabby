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
          keySignatures: staff.bars.map((bar) => [bar.keySignature, bar.keySignatureType]),
          ghost: note(0).isGhost,
          letRing: note(0).isLetRing,
          harmonics: beats[1].notes.map((note) => [note.harmonicType, note.harmonicValue]),
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

    function :version5, <<~JS
      async (base64) => {
        const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(Buffer.from(base64, 'base64'), new alphaTab.Settings());
        const beats = score.tracks[0].staves[0].bars[0].voices[0].beats;
        return {
          tempos: score.masterBars.map((bar) => bar.tempoAutomations.map((automation) => automation.value)),
          beats: beats.map((beat) => ({
            dots: beat.dots, dynamics: beat.dynamics, vibrato: beat.notes[0]?.vibrato ?? null,
            harmonic: beat.notes[0]?.harmonicType ?? null, accent: beat.notes[0]?.accentuated ?? null,
            slideOut: beat.notes[0]?.slideOutType ?? null, tremoloMarks: beat.tremoloPicking?.marks ?? null,
            grace: beat.graceType,
          })),
        };
      }
    JS

    function :voices, <<~JS
      async (base64) => {
        const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(Buffer.from(base64, 'base64'), new alphaTab.Settings());
        return score.tracks[0].staves[0].bars.map((bar) => bar.voices.map((voice) => voice.isEmpty ? 'empty' : voice.beats.length));
      }
    JS

    function :techniques, <<~JS
      async (base64) => {
        const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(Buffer.from(base64, 'base64'), new alphaTab.Settings());
        return score.tracks[0].staves[0].bars[0].voices[0].beats.map((beat) => ({
          slap: beat.slap, pop: beat.pop, tap: beat.tap, brush: [beat.brushType, beat.brushDuration], pickStroke: beat.pickStroke,
          tremoloMarks: beat.tremoloPicking?.marks ?? null, vibrato: beat.notes[0].vibrato,
          trillFret: beat.notes[0].isTrill ? beat.notes[0].trillFret : null,
          slide: [beat.notes[0].slideInType, beat.notes[0].slideOutType],
        }));
      }
    JS

    function :fermatas, <<~JS
      async (base64) => {
        const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(Buffer.from(base64, 'base64'), new alphaTab.Settings());
        return score.masterBars.map((bar) =>
          [...(bar.fermata ?? [])].map(([offset, fermata]) => [offset, fermata.type, fermata.length]));
      }
    JS

    function :clefs, <<~JS
      async (base64) => {
        const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(Buffer.from(base64, 'base64'), new alphaTab.Settings());
        return score.tracks.map((track) => track.staves[0].bars.map((bar) => bar.clef));
      }
    JS

    function :accidental_modes, <<~JS
      async (base64) => {
        const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(Buffer.from(base64, 'base64'), new alphaTab.Settings());
        return score.tracks[0].staves[0].bars[0].voices[0].beats.map((beat) => beat.notes[0].accidentalMode);
      }
    JS
  end

  let(:alpha_tab) { described_class.new }

  def rest_measure(**options)
    whole_rest = { 'type' => 1, 'duration' => [1, 1], 'rest' => true, 'notes' => [{ 'rest' => true }] }
    { 'voices' => [{ 'beats' => [whole_rest] }], **options }
  end
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
        expect(info['tracks'].pluck('isPercussion', 'stringCount')).to eq [[false, 6], [false, 4], [true, 0]]
        expect(info['tracks'].map { Song::Track.from_info(it).instrument_type }).to eq %i[guitar bass drums]
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

    it "repeats as many times as the alternate endings need, like Songsterr, even when the repeat count is lower" do
      repeats = JSON.parse(file_fixture('songsterr/repeats.json').read)
      repeats['measures'][3]['alternateEnding'] = [1, 2, 3]
      repeats['measures'][4]['alternateEnding'] = [4]
      result = alpha_tab.songsterr_to_gp(page.metadata, [repeats])
      expect(result['playedBars']).to eq [
        [0, 0], [1, 0], [2, 0], [3, 0], [1, 1], [2, 1], [3, 1], [1, 2], [2, 2], [3, 2], [1, 3], [2, 3], [4, 0], [5, 0]
      ]
      expect(AlphaTabInspector.new.effects(result['gp'])['repeatCounts']).to eq [0, 0, 0, 4, 0, 0]
    end

    it "maps fermatas, on notes and rests" do
      fermata = ->(type) { { 'fermata' => { 'type' => type, 'length' => 0.51 } } }
      quarter = { 'type' => 4, 'duration' => [1, 4] }
      part = {
        'instrumentId' => 34, 'strings' => 4, 'tuning' => [43, 38, 33, 28],
        'measures' => [
          { 'signature' => [4, 4], 'voices' => [{ 'beats' => [
            { 'type' => 2, 'duration' => [1, 2], 'notes' => [{ 'fret' => 5, 'string' => 2 }], **fermata.('short') },
            quarter.merge('rest' => true, **fermata.('medium')),
            quarter.merge('rest' => true, **fermata.('long'))
          ] }] }
        ]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Fermatas", 'tracks' => [{ 'title' => "Bass" }] }, [part])

      expect(result['warnings']).to eq []
      # by tick offset (960 per quarter note); AlphaTab FermataType values: Short, Medium, Long
      expect(AlphaTabInspector.new.fermatas(result['gp'])).to eq [[[0, 0, 0.51], [1920, 1, 0.51], [2880, 2, 0.51]]]
    end

    it "spells notes as Songsterr does, warning about spellings that don't match the note's pitch" do
      # spn is [step (C = 0), accidental, octave]; the high E string's frets 4 and 3 are G♯4/A♭4 and G4
      spelled = lambda do |fret, spn|
        { 'type' => 4, 'duration' => [1, 4], 'notes' => [{ 'fret' => fret, 'string' => 0, 'spn' => spn }] }
      end
      part = {
        'instrumentId' => 54, 'strings' => 6, 'tuning' => [64, 59, 55, 50, 45, 40],
        'measures' => [
          { 'signature' => [5, 4], 'voices' => [{ 'beats' => [
            spelled.(4, [4, 1, 4]), spelled.(4, [5, -1, 4]), spelled.(3, [4, 0, 4]), spelled.(3, [3, 2, 4]), spelled.(3, [0, 0, 4])
          ] }] }
        ]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Spelling", 'tracks' => [{ 'title' => "Voice" }] }, [part])
      # AlphaTab NoteAccidentalMode values: Default, ForceSharp, ForceFlat, ForceDoubleSharp
      model = { default: 0, sharp: 3, flat: 5, double_sharp: 4 }

      expect(AlphaTabInspector.new.accidental_modes(result['gp']))
        .to eq [model[:sharp], model[:flat], model[:default], model[:double_sharp], model[:default]]
      expect(result['warnings']).to eq ["note.spn=[0,0,4] for pitch 67 (1×)"]
    end

    it "maps Songsterr notation effects" do
      beat = ->(notes, **options) { { 'type' => 4, 'duration' => [1, 4], 'notes' => notes, **options } }
      part = {
        'instrumentId' => 27, 'strings' => 6, 'tuning' => [64, 59, 55, 50, 45, 40],
        'measures' => [
          { 'signature' => [4, 4], 'tripletFeel' => '16th',
            'keySignature' => { 'accidentalCount' => -3, 'mode' => 'major', 'transposeAs' => 'b' },
            'voices' => [{ 'beats' => [
            beat.([{ 'fret' => 5, 'string' => 2, 'ghost' => true }],
                  'letRing' => true, 'chord' => { 'text' => "Asus2", 'width' => 39 }),
            beat.([{ 'fret' => 5, 'string' => 2, 'harmonic' => 'artificial', 'harmonicFret' => 12 },
                   { 'fret' => 6, 'string' => 3, 'harmonic' => 'tapped', 'harmonicFret' => 12 }]),
            beat.([{ 'fret' => 5, 'string' => 2 }], 'vibrato' => true),
            beat.([{ 'fret' => 5, 'string' => 2 }], 'vibratoWithTremoloBar' => 'wide')
          ] }] },
          rest_measure('repeat' => 3),
          { 'doubleBarline' => true, 'keySignature' => { 'accidentalCount' => 1, 'mode' => 'minor', 'transposeAs' => '#' },
            'voices' => [{ 'beats' => [
            { 'type' => 64, 'duration' => [1, 64], 'graceNote' => 'onBeat', 'notes' => [{ 'fret' => 3, 'string' => 2 }] },
            beat.([{ 'fret' => 5, 'string' => 2, 'accentuated' => 2, 'leftHandVibrato' => 'wide' }],
                  'text' => { 'text' => "w/ flanger", 'width' => 60 }, 'gradualVelocity' => 'crescendo'),
            beat.([{ 'fret' => 5, 'string' => 2 }],
                  'tremoloBar' => { 'tone' => 0,
                                    'points' => [{ 'position' => 0, 'tone' => 0 }, { 'position' => 60, 'tone' => -50 }] }),
            beat.([{ 'fret' => 5, 'string' => 2, 'slide' => 'below' }]),
            beat.([{ 'fret' => 5, 'string' => 2 }])
          ] }] },
          rest_measure
        ]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Effects", 'tracks' => [{ 'title' => "Guitar" }] }, [part])
      # AlphaTab enum values
      model = { triplet16th: 1, artificial: 2, tap: 4, slight: 1, wide: 2, on_beat: 1, heavy: 2, crescendo: 1, from_below: 1,
                light_light: 7, error: 4 }

      expect(result['warnings']).to eq []
      expect(AlphaTabInspector.new.effects(result['gp'])).to eq(
        'tripletFeels' => [model[:triplet16th]] * 4, 'repeatCounts' => [0, 3, 0, 0],
        'keySignatures' => [[-3, 0], [-3, 0], [1, 1], [1, 1]], # E♭ major, then E minor
        'ghost' => true, 'letRing' => true, 'harmonics' => [[model[:artificial], 12], [model[:tap], 12]],
        'noteVibrato' => model[:slight], 'beatVibrato' => [0, model[:wide]], 'chord' => "Asus2",
        'grace' => model[:on_beat], 'accent' => model[:heavy], 'leftHandVibrato' => model[:wide], 'text' => "w/ flanger",
        'crescendo' => model[:crescendo], 'whammy' => [true, -2], 'slideIn' => model[:from_below],
        'barLineRight' => model[:light_light],
        'logLevel' => model[:error],
      )
    end

    it "converts dead notes that have no fret" do
      dead_notes = [0, 1, 2].map { { 'string' => it, 'dead' => true } }
      part = {
        'instrumentId' => 30, 'strings' => 6, 'tuning' => [64, 59, 55, 50, 45, 40],
        'measures' => [
          { 'signature' => [4, 4], 'voices' => [{ 'beats' => [{ 'type' => 1, 'duration' => [1, 1], 'notes' => dead_notes }] }] }
        ]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Dead notes", 'tracks' => [{ 'title' => "Guitar" }] }, [part])
      expect(result['gp']).to be_present
      expect(result['warnings']).to eq []
    end

    it "maps Songsterr picking techniques" do
      beat = ->(**options) { { 'type' => 4, 'duration' => [1, 4], 'notes' => [{ 'fret' => 5, 'string' => 2 }], **options } }
      part = {
        'instrumentId' => 36, 'strings' => 4, 'tuning' => [43, 38, 33, 28],
        'measures' => [{ 'signature' => [8, 4], 'voices' => [{ 'beats' => [
          beat.('slapping' => true, 'pickStroke' => 'down',
                'notes' => [{ 'fret' => 5, 'string' => 2, 'wideVibrato' => true, 'slide' => 'belowlegato' }]),
          beat.('brushStroke' => { 'direction' => 'down', 'duration' => 30, 'shift' => 100 }, 'upStroke' => 1, 'popping' => true),
          beat.('brushStroke' => { 'direction' => 'up', 'duration' => 60, 'shift' => 100 }, 'downStroke' => 1),
          beat.('tremolo' => [1, 32], 'tapping' => true, 'arpeggio' => { 'direction' => 'up', 'duration' => 60, 'shift' => 100 },
                'notes' => [{ 'fret' => 5, 'string' => 2, 'trill' => { 'auxiliaryFret' => 7, 'speed' => 62 } }]),
          beat.('notes' => [{ 'string' => 2, 'dead' => true, 'pickScrape' => 'down' }]),
          beat.('notes' => [{ 'fret' => 5, 'string' => 2, 'pickScrape' => 'up' }]),
          # slides in and then out are named by joining their in and out slides
          beat.('notes' => [{ 'fret' => 5, 'string' => 2, 'slide' => 'belowshift' }]),
          beat.('notes' => [{ 'fret' => 5, 'string' => 2, 'slide' => 'abovedownwards' }])
        ] }] }]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Techniques", 'tracks' => [{ 'title' => "Bass" }] }, [part])
      none = { 'slap' => false, 'pop' => false, 'tap' => false, 'brush' => [0, 0], 'pickStroke' => 0, 'tremoloMarks' => nil,
               'vibrato' => 0, 'slide' => [0, 0], 'trillFret' => nil }

      expect(result['warnings']).to eq []
      expect(AlphaTabInspector.new.techniques(result['gp'])).to eq [
        # PickStroke.Down, VibratoType.Wide, SlideInType.IntoFromBelow + SlideOutType.Legato
        none.merge('slap' => true, 'pickStroke' => 2, 'vibrato' => 2, 'slide' => [1, 2]),
        none.merge('brush' => [2, 30], 'pickStroke' => 1, 'pop' => true), # BrushDown, PickStroke.Up
        none.merge('brush' => [1, 60], 'pickStroke' => 2), # BrushUp, PickStroke.Down
        none.merge('tremoloMarks' => 3, 'tap' => true, 'brush' => [3, 60], 'trillFret' => 7), # ArpeggioUp
        none.merge('slide' => [0, 5]), # SlideOutType.PickSlideDown
        none.merge('slide' => [0, 6]), # SlideOutType.PickSlideUp
        none.merge('slide' => [1, 1]), # SlideInType.IntoFromBelow + SlideOutType.Shift
        none.merge('slide' => [2, 4]) # SlideInType.IntoFromAbove + SlideOutType.OutDown
      ]
    end

    it "converts Songsterr's older (version 5) track format" do
      beat = ->(notes, **options) { { 'type' => 4, 'duration' => [1, 4], 'notes' => notes, **options } }
      note = { 'fret' => 5, 'string' => 2 }
      part = {
        'version' => 5, 'instrumentId' => 27, 'strings' => 6, 'tuning' => [64, 59, 55, 50, 45, 40],
        # measure numbers in automations are 1-based, like measure.index
        'automations' => { 'tempo' => [{ 'measure' => 1, 'position' => 0, 'type' => 4, 'bpm' => 97 },
                                       { 'measure' => 2, 'position' => 0, 'type' => 4, 'bpm' => 120 }] },
        'measures' => [
          { 'index' => 1, 'signature' => [4, 4], 'voices' => [{ 'beats' => [
            { 'type' => 8, 'dotted' => true, 'duration' => [3, 16], 'tempo' => { 'type' => 4, 'bpm' => 97 },
              'notes' => [note.merge('velocity' => 'mp', 'accentuated' => true, 'slide' => 'unknown')] },
            { 'type' => 16, 'duration' => [1, 16], 'notes' => [note.merge('grace' => true)] },
            beat.([note], 'wideVibrato' => true),
            beat.([note], 'harmonic' => true),
            beat.([note.merge('tremolo' => true, 'trill' => true)])
          ] }] },
          rest_measure('index' => 2),
          rest_measure('index' => 3)
        ]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Version 5", 'tracks' => [{ 'title' => "Guitar" }] }, [part])
      # AlphaTab enum values
      model = { mp: 3, wide: 2, natural: 1, normal: 1 }
      plain = { 'dots' => 0, 'dynamics' => model[:mp], 'vibrato' => 0, 'harmonic' => 0, 'accent' => 0, 'slideOut' => 0,
                'tremoloMarks' => nil, 'grace' => 0 }

      # trills have no trill fret in this format, so can't be converted
      expect(result['warnings']).to eq ["note.trill (1×)"]
      expect(AlphaTabInspector.new.version5(result['gp'])).to eq(
        'tempos' => [[97], [120], []],
        'beats' => [
          plain.merge('dots' => 1, 'accent' => model[:normal]),
          plain,
          plain.merge('vibrato' => model[:wide]),
          plain.merge('harmonic' => model[:natural]),
          plain.merge('tremoloMarks' => 3)
        ]
      )
    end

    it "changes clefs where measures do, defaulting to the instrument's clef" do
      tracks = [{ 'title' => "Strings" }, { 'title' => "Bass", 'isBassGuitar' => true }]
      strings = {
        'instrumentId' => 50, 'strings' => 6, 'tuning' => [64, 59, 55, 50, 45, 40],
        'measures' => [rest_measure('signature' => [4, 4], 'clef' => 'F4'), rest_measure, rest_measure('clef' => 'G2'), rest_measure]
      }
      bass = { 'instrumentId' => 33, 'strings' => 4, 'tuning' => [43, 38, 33, 28], 'measures' => Array.new(4) { rest_measure } }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Clefs", 'tracks' => tracks }, [strings, bass])

      expect(result['warnings']).to eq []
      # AlphaTab Clef values: F4 = 3, G2 = 4
      expect(AlphaTabInspector.new.clefs(result['gp'])).to eq [[3, 3, 4, 4], [3, 3, 3, 3]]
    end

    it "converts tracks whose bars have different numbers of voices" do
      whole = ->(fret) { { 'type' => 1, 'duration' => [1, 1], 'notes' => [{ 'fret' => fret, 'string' => 2 }] } }
      part = {
        'instrumentId' => 27, 'strings' => 6, 'tuning' => [64, 59, 55, 50, 45, 40],
        'measures' => [
          { 'signature' => [4, 4], 'voices' => [{ 'beats' => [whole.(5)] }] },
          { 'voices' => [{ 'beats' => [whole.(5)] }, { 'beats' => [whole.(7)] }] },
          { 'voices' => [{ 'beats' => [whole.(5)] }] }
        ]
      }
      result = alpha_tab.songsterr_to_gp({ 'title' => "Voices", 'tracks' => [{ 'title' => "Guitar" }] }, [part])
      expect(AlphaTabInspector.new.voices(result['gp'])).to eq [[1, 'empty'], [1, 1], [1, 'empty']]
    end

    it "reports Songsterr keys it doesn't map" do
      part = parts[1].deep_dup
      part['measures'][0]['voices'][0]['beats'][0]['notes'][0]['unknownEffect'] = true
      expect(alpha_tab.songsterr_to_gp(page.metadata, [part])['warnings']).to eq ["note.unknownEffect (1×)"]
    end
  end
end
