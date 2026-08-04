    INCLUDE "ptplayer.i"
    
; sound
SFX_PERIOD      equ 443              ; 8000 Hz
SFX_VOLUME      equ 32


; sound effects priorities (higher value -> higher priority)
SFX_PRI_LASER       equ 255
SFX_PRI_EXPLOSION   equ 228
SFX_PRI_FUEL        equ 235
SFX_PRI_JET         equ 238
SFX_PRI_ENERGY      equ 255
SFX_PRI_PICKUP      equ 225
SFX_PRI_DEAD        equ 255

    SECTION    sounds,DATA_C

    even
sfx_laser:       
    dc.w       0                             ; the first two bytes of sfx must be zero for using ptplayer lib
    incbin     "sfx_laser.raw"
    even
sfx_laser_len   EQU (*-sfx_laser)/2

sfx_explosion:       
    dc.w       0
    incbin     "sfx_explosion.raw"
    even
sfx_explosion_len   EQU (*-sfx_explosion)/2

sfx_fuel:       
    dc.w       0
    incbin     "sfx_fuel.raw"
    even
sfx_fuel_len   EQU (*-sfx_fuel)/2

sfx_jet:       
    dc.w       0
    incbin     "sfx_jet.raw"
    even
sfx_jet_len   EQU (*-sfx_jet)/2

sfx_energy:       
    dc.w       0
    incbin     "sfx_energy.raw"
    even
sfx_energy_len   EQU (*-sfx_energy)/2

sfx_pickup:       
    dc.w       0
    incbin     "sfx_pickup.raw"
    even
sfx_pickup_len   EQU (*-sfx_pickup)/2

sfx_dead:       
    dc.w       0
    incbin     "sfx_death.raw"
    even
sfx_dead_len   EQU (*-sfx_dead)/2

    SECTION    sounds_data,CODE

    ; sound effects table
    xdef       sfx_table
sfx_table:
    ; 0 - laser sound effect
    dc.l       sfx_laser                     ; samples pointer
    dc.w       sfx_laser_len                 ; samples length (bytes)
    dc.w       SFX_PERIOD                    ; period
    dc.w       SFX_VOLUME                    ; volume
    dc.b       -1                            ; channel
    dc.b       SFX_PRI_LASER                 ; priority

    ; 1 - explosion sound effect
    dc.l       sfx_explosion                 ; samples pointer
    dc.w       sfx_explosion_len             ; samples length (bytes)
    dc.w       SFX_PERIOD                    ; period
    dc.w       SFX_VOLUME                    ; volume
    dc.b       -1                            ; channel
    dc.b       SFX_PRI_EXPLOSION             ; priority

    ; 2 - hit sound effect
    dc.l       sfx_fuel                       ; samples pointer
    dc.w       sfx_fuel_len                   ; samples length (bytes)
    dc.w       SFX_PERIOD                    ; period
    dc.w       SFX_VOLUME                    ; volume
    dc.b       -1                            ; channel
    dc.b       SFX_PRI_FUEL                   ; priority

    ; 3 - jet sound effect
    dc.l       sfx_jet
    dc.w       sfx_jet_len              
    dc.w       SFX_PERIOD                 
    dc.w       SFX_VOLUME                  
    dc.b       -1                           
    dc.b       SFX_PRI_JET                   

    ; 4 - energy sound effect
    dc.l       sfx_energy
    dc.w       sfx_energy_len              
    dc.w       SFX_PERIOD                 
    dc.w       SFX_VOLUME                  
    dc.b       -1                           
    dc.b       SFX_PRI_ENERGY                   

    ; 5 - fuel pickup sound effect
    dc.l       sfx_pickup
    dc.w       sfx_pickup_len              
    dc.w       SFX_PERIOD                 
    dc.w       SFX_VOLUME                  
    dc.b       -1                           
    dc.b       SFX_PRI_PICKUP    

    ; 6 - player death pickup sound effect
    dc.l       sfx_dead
    dc.w       sfx_dead_len              
    dc.w       SFX_PERIOD                 
    dc.w       SFX_VOLUME                  
    dc.b       -1                           
    dc.b       SFX_PRI_DEAD    