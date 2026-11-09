# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Song::Track do
  def instrument_type(name, program, percussion: false, strings: 6)
    described_class.new(name:, program:, percussion:, strings:).instrument_type
  end

  it "classifies percussion tracks as drums, whatever the name or program" do
    expect(instrument_type("Drums", 0, percussion: true, strings: 0)).to eq :drums
    expect(instrument_type("Percusión", 0, percussion: true, strings: 0)).to eq :drums
    expect(instrument_type("Bass Drum", 32, percussion: true, strings: 0)).to eq :drums
  end

  it "classifies by General MIDI program" do
    expected = {
      ["Acoustic Grand Piano", 0] => :keys, ["Celesta", 8] => :keys, ["Rock Organ", 18] => :keys, ["Harmonica", 22] => :other,
      ["Distortion Guitar", 30] => :guitar, ["Electric Bass (finger)", 33] => :bass, ["Contrabass", 43] => :bass,
      ["Violin", 40] => :strings, ["Orchestral Harp", 46] => :strings, ["Timpani", 47] => :drums,
      ["String Ensemble 2", 49] => :strings, ["Synth Strings 1", 50] => :keys, ["Choir Aahs", 52] => :vocals,
      ["Synth Voice", 54] => :vocals, ["Trumpet", 56] => :brass, ["Synth Brass 1", 62] => :keys, ["Tenor Sax", 66] => :woodwinds,
      ["Oboe", 68] => :woodwinds, ["Whistle", 78] => :woodwinds, ["Lead 2 (sawtooth)", 81] => :keys, ["Pad 2 (warm)", 89] => :keys,
      ["FX 5 (brightness)", 100] => :keys, ["Sitar", 104] => :other, ["Banjo", 105] => :guitar, ["Fiddle", 110] => :strings,
      ["Reverse Cymbal", 119] => :drums, ["Applause", 126] => :other,
    }
    expect(expected.to_h { |(name, program), _| [[name, program], instrument_type(name, program)] }).to eq expected
  end

  it "classifies bass parts written with a guitar sound by their string count" do
    expect(instrument_type("Track 2", 29, strings: 4)).to eq :bass
    expect(instrument_type("Track 2", 29, strings: 5)).to eq :bass
    expect(instrument_type("Track 1", 30, strings: 7)).to eq :guitar
  end

  # real track names whose program describes the sound rather than the player
  it "prefers a role named in the track name over the program" do
    expect(instrument_type("Bass", 29)).to eq :bass
    expect(instrument_type("Bass Dist - Distortion Guitar", 30)).to eq :bass
    expect(instrument_type("Basse", 30)).to eq :bass
    expect(instrument_type("Backing Vocals - Accordion", 21)).to eq :vocals
    expect(instrument_type("Backing Vocals - Choir Aahs", 52)).to eq :vocals
    expect(instrument_type("David Sancious - Keyboards - String Ensemble 2", 49)).to eq :keys
    expect(instrument_type("Kevin Moore - Keyboard III - FX 5 (brightness)", 100)).to eq :keys
    expect(instrument_type("Jordan Rudess - Synth Brass - Synth Brass 1", 62)).to eq :keys
    expect(instrument_type("Mike Mills | Piano - Acoustic Grand Piano", 0)).to eq :keys
    expect(instrument_type("Lead Guitar", 0)).to eq :guitar
    expect(instrument_type("Roddy Bottum - Syn. Brass - Trumpet", 56)).to eq :keys
    expect(instrument_type("Cliff Burton | Distortion Effect - Electric Bass (finger)", 33)).to eq :bass
  end

  it "ignores General MIDI patch names echoed in the track name" do
    expect(instrument_type("Geddy Lee - Lead 6 (voice)", 85)).to eq :keys
    expect(instrument_type("Don Airey - Pad - Lead 6 (voice)", 85)).to eq :keys
    expect(instrument_type("Electric Bass (finger)", 33)).to eq :bass
    expect(instrument_type("Synth Bass - Lead 8 (bass + lead)", 87, strings: 4)).to eq :keys
    expect(instrument_type("Chris Wolstenholme | Roland JP-8000 | Sawtooth Bass Effect - Lead 2 (sawtooth)", 81)).to eq :bass
  end

  it "doesn't mistake other instruments named after bass for bass" do
    expect(instrument_type("Bass Clarinet", 71)).to eq :woodwinds
    expect(instrument_type("Bass Trombone", 57)).to eq :brass
  end

  it "falls back to the program for names that don't name a role" do
    expect(instrument_type("Ending Solo", 30)).to eq :guitar
    expect(instrument_type("Pista 3", 33)).to eq :bass
    expect(instrument_type(nil, 66)).to eq :woodwinds
  end

  it "builds from AlphaTab track info" do
    info = AlphaTab.new.score_info(file_fixture('Practice Etude.gp').to_s)
    track = described_class.from_info(info['tracks'].sole)
    expect(track).to have_attributes(name: "Electric Bass", program: 33, percussion: false, strings: 4)
    expect(track.instrument_type).to eq :bass
  end
end
