# frozen_string_literal: true

# A score track, as described by AlphaTab (see AlphaTab#score_info), classified by the type of instrument that plays it.
#
# The MIDI program is the main signal, but it describes the sound rather than the player: keyboard players use synth brass and
# string patches, bass parts are sometimes written with a guitar sound, and vocal parts with a choir or accordion.  So a role
# named in the track name wins over the program, after removing any General MIDI patch name that's merely echoed in it (e.g.
# "Geddy Lee - Lead 6 (voice)" is a synth, not vocals).
class Song::Track < Data.define(:name, :program, :percussion, :strings)
  GENERAL_MIDI_NAMES = [
    # piano
    "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano", "Honky-tonk Piano",
    "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clavinet",
    # chromatic percussion
    "Celesta", "Glockenspiel", "Music Box", "Vibraphone", "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
    # organ
    "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ", "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
    # guitar
    "Acoustic Guitar (nylon)", "Acoustic Guitar (steel)", "Electric Guitar (jazz)", "Electric Guitar (clean)",
    "Electric Guitar (muted)", "Overdriven Guitar", "Distortion Guitar", "Guitar Harmonics",
    # bass
    "Acoustic Bass", "Electric Bass (finger)", "Electric Bass (pick)", "Fretless Bass",
    "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
    # strings
    "Violin", "Viola", "Cello", "Contrabass", "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
    # ensemble
    "String Ensemble 1", "String Ensemble 2", "Synth Strings 1", "Synth Strings 2",
    "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
    # brass
    "Trumpet", "Trombone", "Tuba", "Muted Trumpet", "French Horn", "Brass Section", "Synth Brass 1", "Synth Brass 2",
    # reed
    "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax", "Oboe", "English Horn", "Bassoon", "Clarinet",
    # pipe
    "Piccolo", "Flute", "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
    # synth lead
    "Lead 1 (square)", "Lead 2 (sawtooth)", "Lead 3 (calliope)", "Lead 4 (chiff)",
    "Lead 5 (charang)", "Lead 6 (voice)", "Lead 7 (fifths)", "Lead 8 (bass + lead)",
    # synth pad
    "Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)", "Pad 4 (choir)",
    "Pad 5 (bowed)", "Pad 6 (metallic)", "Pad 7 (halo)", "Pad 8 (sweep)",
    # synth effects
    "FX 1 (rain)", "FX 2 (soundtrack)", "FX 3 (crystal)", "FX 4 (atmosphere)",
    "FX 5 (brightness)", "FX 6 (goblins)", "FX 7 (echoes)", "FX 8 (sci-fi)",
    # ethnic
    "Sitar", "Banjo", "Shamisen", "Koto", "Kalimba", "Bagpipe", "Fiddle", "Shanai",
    # percussive
    "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock", "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
    # sound effects
    "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet", "Telephone Ring", "Helicopter", "Applause", "Gunshot",
  ].freeze

  # Roles named in track names, in priority order (e.g. "Keyboard Bass" is keys, "Backing Vocals - Guitar" is vocals)
  NAMED_TYPES = {
    vocals: /\b(vocals?|vox|voices?|choir|singer|voz|gesang)\b/i,
    keys:   /\b(keys|keyboards?|synth\w*|syn|piano|organ|clavinet|rhodes|wurlitzer|mellotron|moog)\b/i,
    bass:   /\b(bass[eo]?|bajo|baixo)\b(?!\s*(clarinet|trombone|flute|sax|saxophone|drum))/i,
    guitar: /\b(guitars?|gtr|guitarra|chitarra|gitarre)\b/i,
  }.freeze

  # Builds a Track from an AlphaTab#score_info track
  def self.from_info(info)
    new(
      name: info['name'],
      program: info.dig('playbackInfo', 'program'),
      percussion: info['isPercussion'],
      strings: info['stringCount'],
    )
  end

  def self.general_midi_name?(name)
    @general_midi_names ||= GENERAL_MIDI_NAMES.to_set { normalize_name(it) }
    @general_midi_names.include?(normalize_name(name))
  end

  # e.g. "Lead 8 (bass + lead)" => "lead8bassandlead", as AlphaTab names it
  def self.normalize_name(name) = name.downcase.gsub('+', 'and').gsub(/[^a-z0-9]/, '')

  def instrument_type
    return :drums if percussion

    named_type || program_type
  end

  private

  def named_type
    NAMED_TYPES.find { |_type, pattern| role_name.match?(pattern) }&.first
  end

  # The track name, without any General MIDI patch names in its " - " or " | " separated parts
  def role_name
    name.to_s.split(/\s+[-|]\s+/).reject { self.class.general_midi_name?(it) }.join(' - ')
  end

  def program_type
    case program
      when 0..21, 23  then :keys      # piano, chromatic percussion, organ, accordion
      when 22         then :other     # harmonica
      when 24..31     then (4..5).include?(strings) ? :bass : :guitar # bass parts are sometimes written with a guitar sound
      when 32..39, 43 then :bass      # including contrabass, i.e. upright bass
      when 40..46     then :strings   # including harp
      when 47         then :drums     # timpani
      when 48, 49     then :strings
      when 50, 51     then :keys      # synth strings
      when 52..54     then :vocals    # choir, voice, synth voice
      when 55         then :keys      # orchestra hit
      when 56..61     then :brass
      when 62, 63     then :keys      # synth brass
      when 64..79     then :woodwinds
      when 80..103    then :keys      # synth lead, pad, and effects
      when 105        then :guitar    # banjo
      when 109, 111   then :woodwinds # bagpipe, shanai
      when 110        then :strings   # fiddle
      when 112..119   then :drums
      else                 :other     # sitar, shamisen, koto, kalimba, sound effects
    end
  end
end
