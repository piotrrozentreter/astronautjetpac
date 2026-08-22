    SECTION music_data,DATA_C

    XDEF music
    XDEF music1
    XDEF music2

    even

music:
    incbin "music.mod"
    even
music1:
    incbin "music1.mod"
    even
music2:
    ;comment this out for 1MB build
    ;incbin "music2.mod"