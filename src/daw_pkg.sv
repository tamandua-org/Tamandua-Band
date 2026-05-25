package daw_pkg;

    // Global
    localparam MAX_NOTES = 6;
    localparam PATTERN_LENGTH = 64; // 4 semiquavers * 4 beats * 4 bars
    localparam NUM_PATTERNS = 20;
    localparam BPM_BITS = 8;  // 1 - 255 BPM 

    // Bit Widths
    localparam PATTERN_ID_BITS = 5;  // 5 bits addresses up to 32 patterns
    localparam NOTE_DELTA_BITS = 7;  // 7-bit delta + 1-bit active flag = 8 bits per cell
    localparam SONG_POS_BITS = 16; // 16 bits = max ~65k semiquavers (~1.5 hours at 120BPM)

    typedef enum logic [3:0] {
        PIANO,
        SNARE,
        KICK,
        HIHAT,
        TRUMPET,
        SYNTH,
        GUITAR
    } instrument_t;

    // -64 to +63
    typedef logic signed [NOTE_DELTA_BITS-1:0] note_delta_t;

    // pattern cell
    typedef struct packed {
        logic active;     // 1 bit
        note_delta_t note_delta; // 7 bits
    } cell_t;


    // 6 notes x 7 bits per note x 64 semiquavers = 2688 bits + 4 bits instrumentId
    typedef struct packed {
        instrument_t instrument_id;
        cell_t [MAX_NOTES-1:0][PATTERN_LENGTH-1:0] cells; // [row/note][column/semiquaver slot]
    } pattern_t;


    // An ordered array of these will make up a track timeline
//    typedef struct packed {
//        logic valid;
//        logic [SONG_POS_BITS-1:0] start_semiquaver; // time pos
//        logic [PATTERN_ID_BITS-1:0] pattern_id;
//        instrument_t instrument;
//    } track_entry_t;


    // Note event fired by the pattern engine into the voice slot allocator
    typedef struct packed {
        instrument_t instrument_id;
        note_delta_t note_delta;
        end_mode_t   end_mode;
    } note_event_t;

endpackage