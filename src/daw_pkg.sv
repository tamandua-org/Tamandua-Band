package daw_pkg;

    // Global
    localparam MAX_NOTES = 6;
    localparam PATTERN_LENGTH = 64; // 4 semiquavers * 4 beats * 4 bars
    localparam NUM_PATTERNS = 10;
    localparam BPM_BITS = 8;  // 1 - 255 BPM 
    localparam NUM_VOICES = 66; // 10 patterns x 6 notes + 6 notes live play

    // Bit Widths
    localparam PATTERN_ID_BITS = 4;  // 4 bits addresses up to 16 patterns PATTERN 4'b1111 is reserved for live notes
    localparam NOTE_DELTA_BITS = 7;  // 7-bit delta + 1-bit active flag = 8 bits per cell
    localparam SONG_POS_BITS = 16; // 16 bits = max ~65k semiquavers (~1.5 hours at 120BPM)
    
    typedef enum logic {
        NATURAL = 1'b0,  // play to sample end (drumkit, piano)
        GATED   = 1'b1   // loop until note off event (trumpet, synth)
    } end_mode_t;
    
    typedef enum logic [3:0] {
        PIANO = 0,
        SNARE,
        KICK,
        HIHAT,
        TRUMPET,
        SYNTH,
        GUITAR
    } instrument_t;

    // 0 to 127
    typedef logic [NOTE_DELTA_BITS-1:0] note_delta_t;

    // pattern cell
    typedef struct packed {
        logic active;     // 1 bit
        note_delta_t note_delta; // 7 bits
    } cell_t;

    //UNUSED
    // 6 notes x 7 bits per note x 64 semiquavers = 2688 bits + 4 bits instrumentId
    typedef struct packed { 
        instrument_t instrument_id;
        cell_t [MAX_NOTES-1:0][PATTERN_LENGTH-1:0] cells; // [row/note][column/semiquaver slot]
    } pattern_t;

    typedef struct packed {
        cell_t [MAX_NOTES-1:0] notes; // notes[0] to notes[5]
    } pattern_col_t;  

    // Note event fired by the pattern engine into the voice slot allocator
    typedef struct packed { //size: 4 + 7 + 4 + 1 = 16
        instrument_t instrument_id;
        note_delta_t note_delta;
        logic [PATTERN_ID_BITS-1:0] pattern_id;
        logic is_on_event;
    } note_event_t;
    
    // states of ADSR envelope
    typedef enum logic [2:0] {
        ENV_OFF,
        ENV_ATTACK,
        ENV_DECAY,
        ENV_SUSTAIN,
        ENV_RELEASE
    } env_state_t;

    // Defines how an instrument loops and fades
    typedef struct packed {
        logic [23:0] start_addr; // por ahora 
        logic [23:0] end_addr;
        logic [23:0] loop_start;
        end_mode_t   mode;          // NATURAL or GATED
        
        // ADSR Math: Added/subtracted per 48kHz tick (0 to 65535)
        logic [15:0] attack_rate;   
        logic [15:0] decay_rate;    
        logic [15:0] sustain_level; 
        logic [15:0] release_rate;
    } instrument_meta_t;

    function automatic instrument_meta_t get_instrument_meta(instrument_t inst);
        case (inst)
                    //     START      END        LOOP       MODE       A          D          S          R
            KICK:  return '{24'd0,     24'd10000, 24'd0,     NATURAL, 16'd65000, 16'd0,     16'd65535, 16'd65000}; 
            SNARE: return '{24'd10000, 24'd25000, 24'd0,     NATURAL, 16'd65000, 16'd0,     16'd65535, 16'd65000};
            PIANO: return '{24'd25000, 24'd80000, 24'd0,     GATED,   16'd5000,  16'd100,   16'd30000, 16'd500};   
            SYNTH: return '{24'd80000, 24'd82000, 24'd80500, GATED,   16'd1000,  16'd50,    16'd40000, 16'd200};   
            default: return '{24'd0, 24'd1000, 24'd0, NATURAL, 16'd65535, 16'd0, 16'd65535, 16'd65535};
        endcase
    endfunction

endpackage