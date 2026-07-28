    SECTION music_data,DATA_C

    XDEF music
    XDEF music1

    even

music:
    incbin "music.mod"
    even
music1:
    incbin "music1.mod"