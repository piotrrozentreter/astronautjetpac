letter_x        EQU 0
letter_y        EQU 4
letter_dx       EQU 8
letter_dy       EQU 12
letter_speedx   EQU 16
letter_speedy   EQU 20
letter_active   EQU 24
LETTER_SIZE     EQU 28  ; size of one letter structure

    XDEF move_letters

    XREF letters_active
    XREF letter

    SECTION main,code
    cnop 0,4

move_letters:
            ; Check if any letter is active (letters_active != 0)
            move.b letters_active,d0
            tst.b d0
            beq .end_function

            clr.l d0              ; D0 = t (loop counter)
            lea letter,a0      ; A0 = address of the start of letter array

.loop_start:
            cmp.l #8,d0
            bge .end_function

            ; Check if letter[t].active == 1
            move.l letter_active(a0),d1
            cmp.l #1,d1
            bne .next_sprite     ; if inactive, go to next

            ; Load x and y
            move.l letter_x(a0),d1    ; D1 = x
            move.l letter_y(a0),d2    ; D2 = y

            ; Add offsets dx and dy
            add.l letter_dx(a0),d1
            add.l letter_dy(a0),d2

            ; --- Check X boundaries ---
            tst.l d1
            blt .reset_x_min     ; if x < 0
            cmp.l #272,d1
            bgt .reset_x_max     ; if x > METEOR_START_X
            bra .check_y         ; otherwise check Y

.reset_x_max:
            move.l #272,d1
            move.l letter_speedx(a0),d3
            neg.l d3              ; dx = -speedx
            move.l d3,letter_dx(a0)
            bra .check_y

.reset_x_min:
            clr.l d1              ; x = 0
            move.l letter_speedx(a0),letter_dx(a0) ; dx = speedx

.check_y:
            ; --- Check Y boundaries ---
            tst.l d2
            blt .reset_y_min     ; if y < 0
            cmp.l #(176+26),D2
            bgt .reset_y_max     ; if y > METEOR_MAX_Y
            bra .do_update

.reset_y_max:
            move.l #(176+26),d2
            move.l letter_speedy(a0),d3
            neg.l d3              ; dy = -speedy
            move.l d3,letter_dy(a0)
            bra .do_update

.reset_y_min:
            clr.l d2              ; y = 0
            move.l letter_speedy(a0),letter_dy(a0) ; dy = speedy

.do_update:
            ; Save new x and y values to the structure
            move.l d1,letter_x(a0)
            move.l d2,letter_y(a0)

.next_sprite:
            add.l #LETTER_SIZE,a0 ; move to next structure (LETTER_SIZE)
            addq.l #1,d0           ; t++
            bra .loop_start

.end_function:
            rts
