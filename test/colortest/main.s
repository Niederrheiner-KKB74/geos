; COLORTEST - test application for ColorCard / ColorRectangle on MEGA65
;
; Draws a 50% grey pattern and colours it:
;   - 16 full-width bars with ColorRectangle, foreground colour = bar number,
;     background colour = 15 - bar number
;   - a row of single cards with ColorCard (write), alternating red/yellow
;   - reads every bar back with ColorCard (read) and prints OK / FAILED
; Click or press a key to return to the desktop.

.include "const.inc"
.include "geossym.inc"
.include "geossym2.inc"
.include "geosmac.inc"

.export __STARTUP_RUN__

BAR_TOP		= 24		; first bar starts at this scanline
CARD_ROW	= BAR_TOP + 16*8 + 8

.segment "STARTUP"

__STARTUP_RUN__:
	; whole screen: 50% pattern, so foreground and background are visible
	lda #2
	jsr SetPattern
	LoadB r2L, 0
	MoveB screenMaxY, r2H
	LoadW r3, 0
	lda screenMaxY+1	; bits 8-11 of bottom go into r4H's upper nibble
	asl
	asl
	asl
	asl
	ora screenMaxX+1
	sta r4H
	MoveB screenMaxX, r4L
	jsr Rectangle

	; 16 bars with ColorRectangle
	LoadB barNo, 0
@bar:	jsr BarRect
	jsr BarColor
	jsr ColorRectangle
	inc barNo
	CmpBI barNo, 16
	bne @bar

	; row of single cards with ColorCard (write)
	LoadW r3, 0
	LoadB r11L, CARD_ROW
@card:	lda r3L
	and #8
	beq @red
	lda #(BLACK << 4) + YELLOW
	bne @set
@red:	lda #(WHITE << 4) + RED
@set:	sec
	jsr ColorCard
	AddVW 8, r3
	CmpWI r3, 256
	bne @card

	; read all bars back with ColorCard (read)
	LoadB errors, 0
	LoadB barNo, 0
@chk:	LoadW r3, 100
	lda barNo
	asl
	asl
	asl
	clc
	adc #BAR_TOP + 3
	sta r11L
	clc
	jsr ColorCard
	sta readVal
	jsr BarColor
	cmp readVal
	beq @ok
	inc errors
@ok:	inc barNo
	CmpBI barNo, 16
	bne @chk

	; result text line: black on light grey, pattern cleared
	LoadB r2L, 0
	LoadB r2H, 15
	LoadW r3, 0
	MoveB screenMaxX, r4L
	lda screenMaxX+1
	sta r4H
	lda #(BLACK << 4) + LTGREY
	jsr ColorRectangle
	lda #0
	jsr SetPattern
	jsr Rectangle		; same area, cleared
	jsr UseSystemFont
	LoadW r0, txtTitle
	LoadW r11, 8
	LoadB r1H, 10
	jsr PutString
	LoadW r0, txtOK
	lda errors
	beq @print
	LoadW r0, txtFail
@print:	jsr PutString

	; exit on click or key
	LoadW otherPressVec, ExitPress
	LoadW keyVector, Exit
	clc
	jsr StartMouseMode
	rts

ExitPress:
	lda mouseData
	bmi @1			; ignore release
	jmp EnterDeskTop
@1:	rts
Exit:	jmp EnterDeskTop

; r2/r3/r4 = rectangle of bar barNo (full width, 8 scanlines)
BarRect:
	lda barNo
	asl
	asl
	asl
	clc
	adc #BAR_TOP
	sta r2L
	clc
	adc #7
	sta r2H
	LoadW r3, 0
	MoveW screenMaxX, r4
	rts

; a = colour of bar barNo: foreground = barNo, background = 15 - barNo
BarColor:
	lda barNo
	asl
	asl
	asl
	asl
	sta readTmp
	lda #15
	sec
	sbc barNo
	ora readTmp
	rts

txtTitle:
	.byte BOLDON, "MEGA65 ColorCard/ColorRectangle test", PLAINTEXT
	.byte " - read back: ", NULL
txtOK:	.byte "OK  (click or key = exit)", NULL
txtFail:
	.byte "FAILED  (click or key = exit)", NULL

barNo:	 .byte 0
errors:	 .byte 0
readVal: .byte 0
readTmp: .byte 0
