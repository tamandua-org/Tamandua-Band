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
        BRASS,
        GUITAR
    } instrument_t;
    
    localparam instrument_t FIRST_INSTRUMENT = PIANO;
    localparam instrument_t LAST_INSTRUMENT = GUITAR;

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
        logic [23:0] start_addr; 
        logic [23:0] end_addr; // end indicates the last index included
        logic [23:0] loop_start;
        end_mode_t   mode;          // NATURAL or GATED
        
        // ADSR Math: Added/subtracted per 48kHz tick (0 to 65535)
        logic [15:0] attack_rate;   
        logic [15:0] decay_rate;    
        logic [15:0] sustain_level; 
        logic [15:0] release_rate;
    } instrument_meta_t;

    function automatic instrument_meta_t get_instrument_meta(input instrument_t inst);
        case (inst)
                    //     START      END        LOOP       MODE       A          D          S          R
            PIANO: return '{24'd0, 24'd37839, 24'd29000,     GATED,   16'd5000,  16'd3,   16'd8500, 16'd5}; 
            SNARE: return '{24'd37840, 24'd50274, 24'd0, NATURAL, 16'd60, 16'd15, 16'd45000, 16'd50};
            HIHAT: return '{24'd50275, 24'd56640, 24'd0, NATURAL, 16'd60, 16'd15, 16'd45000, 16'd50};
            SYNTH: return '{24'd56641, 24'd57292, 24'd56966, GATED,   16'd35,  16'd50, 16'd40000, 16'd40};
            BRASS: return '{24'd56641, 24'd56966, 24'd56641, GATED,   16'd35,  16'd50, 16'd40000, 16'd40};
            GUITAR: return '{24'd57293, 24'd64229, 24'd60761, GATED,   16'd12000,  16'd1, 16'd5000, 16'd2};
              
            default: return '{24'd0, 24'd1000, 24'd0, NATURAL, 16'd65535, 16'd0, 16'd65535, 16'd65535};
        endcase
    endfunction
    
    const logic [23:0] PITCH_STEP_LUT [0:127] = '{
        24'd1024    , // MIDI 0
        24'd1085    , // MIDI 1
        24'd1149    , // MIDI 2
        24'd1218    , // MIDI 3
        24'd1290    , // MIDI 4
        24'd1367    , // MIDI 5
        24'd1448    , // MIDI 6
        24'd1534    , // MIDI 7
        24'd1625    , // MIDI 8
        24'd1722    , // MIDI 9
        24'd1825    , // MIDI 10
        24'd1933    , // MIDI 11
        24'd2048    , // MIDI 12
        24'd2170    , // MIDI 13
        24'd2299    , // MIDI 14
        24'd2435    , // MIDI 15
        24'd2580    , // MIDI 16
        24'd2734    , // MIDI 17
        24'd2896    , // MIDI 18
        24'd3069    , // MIDI 19
        24'd3251    , // MIDI 20
        24'd3444    , // MIDI 21
        24'd3649    , // MIDI 22
        24'd3866    , // MIDI 23
        24'd4096    , // MIDI 24
        24'd4340    , // MIDI 25
        24'd4598    , // MIDI 26
        24'd4871    , // MIDI 27
        24'd5161    , // MIDI 28
        24'd5468    , // MIDI 29
        24'd5793    , // MIDI 30
        24'd6137    , // MIDI 31
        24'd6502    , // MIDI 32
        24'd6889    , // MIDI 33
        24'd7298    , // MIDI 34
        24'd7732    , // MIDI 35
        24'd8192    , // MIDI 36
        24'd8679    , // MIDI 37
        24'd9195    , // MIDI 38
        24'd9742    , // MIDI 39
        24'd10321   , // MIDI 40
        24'd10935   , // MIDI 41
        24'd11585   , // MIDI 42
        24'd12274   , // MIDI 43
        24'd13004   , // MIDI 44
        24'd13777   , // MIDI 45
        24'd14596   , // MIDI 46
        24'd15464   , // MIDI 47
        24'd16384   , // MIDI 48
        24'd17358   , // MIDI 49
        24'd18390   , // MIDI 50
        24'd19484   , // MIDI 51
        24'd20643   , // MIDI 52
        24'd21870   , // MIDI 53
        24'd23170   , // MIDI 54
        24'd24548   , // MIDI 55
        24'd26008   , // MIDI 56
        24'd27554   , // MIDI 57
        24'd29193   , // MIDI 58
        24'd30929   , // MIDI 59
        24'd32768   , // MIDI 60
        24'd34716   , // MIDI 61
        24'd36781   , // MIDI 62
        24'd38968   , // MIDI 63
        24'd41285   , // MIDI 64
        24'd43740   , // MIDI 65
        24'd46341   , // MIDI 66
        24'd49097   , // MIDI 67
        24'd52016   , // MIDI 68
        24'd55109   , // MIDI 69
        24'd58386   , // MIDI 70
        24'd61858   , // MIDI 71
        24'd65536   , // MIDI 72
        24'd69433   , // MIDI 73
        24'd73562   , // MIDI 74
        24'd77936   , // MIDI 75
        24'd82570   , // MIDI 76
        24'd87480   , // MIDI 77
        24'd92682   , // MIDI 78
        24'd98193   , // MIDI 79
        24'd104032  , // MIDI 80
        24'd110218  , // MIDI 81
        24'd116772  , // MIDI 82
        24'd123715  , // MIDI 83
        24'd131072  , // MIDI 84
        24'd138866  , // MIDI 85
        24'd147123  , // MIDI 86
        24'd155872  , // MIDI 87
        24'd165140  , // MIDI 88
        24'd174960  , // MIDI 89
        24'd185364  , // MIDI 90
        24'd196386  , // MIDI 91
        24'd208064  , // MIDI 92
        24'd220436  , // MIDI 93
        24'd233544  , // MIDI 94
        24'd247431  , // MIDI 95
        24'd262144  , // MIDI 96
        24'd277732  , // MIDI 97
        24'd294247  , // MIDI 98
        24'd311744  , // MIDI 99
        24'd330281  , // MIDI 100
        24'd349920  , // MIDI 101
        24'd370728  , // MIDI 102
        24'd392772  , // MIDI 103
        24'd416128  , // MIDI 104
        24'd440872  , // MIDI 105
        24'd467088  , // MIDI 106
        24'd494862  , // MIDI 107
        24'd524288  , // MIDI 108
        24'd555464  , // MIDI 109
        24'd588493  , // MIDI 110
        24'd623487  , // MIDI 111
        24'd660561  , // MIDI 112
        24'd699841  , // MIDI 113
        24'd741455  , // MIDI 114
        24'd785544  , // MIDI 115
        24'd832255  , // MIDI 116
        24'd881744  , // MIDI 117
        24'd934175  , // MIDI 118
        24'd989724  , // MIDI 119
        24'd1048576 , // MIDI 120
        24'd1110928 , // MIDI 121
        24'd1176987 , // MIDI 122
        24'd1246974 , // MIDI 123
        24'd1321123 , // MIDI 124
        24'd1399681 , // MIDI 125
        24'd1482910 , // MIDI 126
        24'd1571089  // MIDI 127
    };
    
    function automatic logic [23:0] midi_to_pitch_step(input note_delta_t midi_note);
        return PITCH_STEP_LUT[midi_note];
    endfunction

endpackage