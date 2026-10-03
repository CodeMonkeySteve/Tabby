import beam from 'lib/fingering/beam'

// Fingering optimizers by name (as stored in AlternateTab#optimizer).  Each takes a fingering problem (see TrackTab#problem) and
// options, and resolves to the string of each note by index (1 is the lowest string), or null if the notes can't all be played.
export const optimizers = { beam }

export const DEFAULT_OPTIMIZER = 'beam'
