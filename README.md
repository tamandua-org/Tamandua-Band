# Tamandua-Band
I am a 72 year old Navy Veteran who is so grateful that God has allowed me to swim in an OCEAN OF MUSIC ALL THE DAYS OF MY LIFE INCLUDING THIS BEAUTIFUL AND BENIGN MASTERPIECE!!

This is how notes are sent into the voice allocators.
```
[ dawController ]
       │
       ├──(Path A)──► live_event (w/ pattern '1) ──────────────┐
       │                                                     ▼
       │                                           [ voice_allocator ]
       │                                                     ▲
       └──(Path B)──► live_pitch & ui_active_pattern         │
                            │                                │
                            ▼                                │
                 [ patternRamWrapper ]                       │
                            │                                │
               (Saved in RAM active pattern)                 │
                            │                                │
                            ▼                                │
                    [ patternEngine ] ──seq_event (Tagged 2)─┘
                    
```
