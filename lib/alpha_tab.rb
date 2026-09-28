# frozen_string_literal: true

# Nodo.debug = true
Nodo.modules_root = "#{__dir__}/alpha_tab/node_modules"
class AlphaTab < Nodo::Core
  require alphaTab: '@coderline/alphatab'
  require :fs

  function :score_info, <<~JS
    async (path) => {
      const settings = new alphaTab.Settings();

      const fileData = await fs.promises.readFile(path);
      const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(new Uint8Array(fileData), settings);

      // see https://alphatab.net/docs/reference/types
      const scoreInfo = { path: path, tracks: [] };
      ['album', 'artist', 'copyright', 'instructions', 'music', 'notices', 'subTitle', 'tab', 'tempo', 'title', 'words'].forEach(scoreKey => {
        const value = score[scoreKey];
        if ((value !== undefined) && (value !== null) && (value !== "")) {
          scoreInfo[scoreKey] = value;
        }
      })
      score.tracks.forEach(track => {
        const trackInfo = {};
        ['playbackInfo', 'name', 'isVisibleOnMultiTrack', 'shortName', 'lineBreaks'].forEach(trackKey => {
          const value = track[trackKey];
          if ((value !== undefined) && (value !== null) && (value !== "")) {
            trackInfo[trackKey] = value;
          }
        })
        trackInfo.isPercussion = track.staves.some(staff => staff.isPercussion);
        trackInfo.stringCount = track.staves[0]?.tuning?.length || 0;
        scoreInfo.tracks[track.index] = trackInfo;
      })

      return scoreInfo;
    }
  JS

  # Converts Songsterr page metadata and track JSON into a Guitar Pro 7 file; see lib/alpha_tab/songsterr_to_gp.js
  function :songsterr_to_gp, File.read("#{__dir__}/alpha_tab/songsterr_to_gp.js"), timeout: 120
end
