; GEOS KERNAL for MEGA65
;
; Colour per 8x8 card: ColorCard and ColorRectangle syscalls
; (GEOS 128 2.0 API) and colour RAM reset on video mode changes.
;
; Every 8x8 card of the bitmap has one colour byte, using the C64 GEOS
; convention: high nibble = colour of set pixels (foreground), low nibble =
; colour of cleared pixels (background), e.g. screencolors = $BF.
; The 16 colours come from the MEGA65 palette and can be redefined there.
;
; The colour RAM address of the current mode (VIC-IV screen pointer
; $D060-$D063) is remembered by InitVideoMode in colorBase; it is accessed
; with 32 bit flat addressing, so no memory mapping is needed:
;   320x200: $0008C00 (COLOR_MATRIX), all other modes: $004E000.
; Rows are screenCardsX bytes apart.
;
; This code lives in the underlay ($A000-$BFFF) and must be called with the
; underlay mapped in (see the _map_ wrappers in kernal/c65/map.s).

.include "const.inc"
.include "geossym.inc"
.include "geosmac.inc"
.include "config.inc"
.include "kernal.inc"
.include "c64.inc"

.import screenCardsX		; scrFullCardsX comes from geossym.inc
.import _NormalizeY

.global _ColorCard
.global _ColorRectangle
.global ResetColors65
.global colorBase

.segment "color65"

; 28 bit address of the colour RAM of the current mode, set by InitVideoMode
colorBase:	.byte 0, 0, 0, 0

colorVal:	.byte 0		; colour to write / colour read
colorWrite:	.byte 0		; ColorCard: 1 = write, 0 = read
colorCX:	.byte 0		; card column
colorCY:	.byte 0		; card row
colorW:		.byte 0		; width in cards - 1
colorRows:	.byte 0		; height in cards

;---------------------------------------------------------------
; ColorCard
;
; Pass:      r3   x position in pixels
;            r11L y position in scanlines (low byte); in the
;                 MEGA65 extended modes the upper 4 bits of r3H
;                 hold bits 8-11 of y, as for GetScanLine
;            a    colour (write only)
;            carry set: write colour, carry clear: read colour
; Return:    a    colour of the card (read)
;            r3, r11L unchanged
; Destroyed: x, y, r5
;---------------------------------------------------------------
_ColorCard:
	sta colorVal
	lda #0
	rol			; carry -> write flag
	sta colorWrite
	PushW r3
	PushB r11L
	PushW r6
	ldx #r3
	ldy #r11L
	jsr _NormalizeY
	ldx #r3
	lda r11L
	jsr GetCard
	jsr CardAddr
	phz
	ldz #0
	lda colorWrite
	beq @read
	lda colorVal
	eom
	sta (r5),z
	bra @done
@read:	eom
	lda (r5),z
	sta colorVal
@done:	plz
	PopW r6
	PopB r11L
	PopW r3
	lda colorWrite
	lsr			; restore carry
	lda colorVal
	rts

;---------------------------------------------------------------
; ColorRectangle
;
; Pass:      a    colour
;            r2L  top (scanlines), r2H bottom
;            r3   left (pixels),   r4  right
;            as for Rectangle: in the MEGA65 extended modes the
;            upper 4 bits of r3H/r4H hold bits 8-11 of top/bottom
; Return:    r2, r3, r4 unchanged
; Destroyed: a, x, y, r5
;---------------------------------------------------------------
_ColorRectangle:
	sta colorVal
	PushW r2
	PushW r3
	PushW r4
	PushW r6
	ldx #r3
	ldy #r2L
	jsr _NormalizeY
	ldx #r4
	ldy #r2H
	jsr _NormalizeY
	ldx #r4			; bottom right card
	lda r2H
	jsr GetCard
	lda colorCX
	pha
	lda colorCY
	pha
	ldx #r3			; top left card
	lda r2L
	jsr GetCard
	pla
	sec
	sbc colorCY
	tax			; rows - 1
	pla
	bcc @done		; bottom above top
	sec
	sbc colorCX
	bcc @done		; right left of left
	sta colorW
	inx
	stx colorRows
	jsr FillCards
@done:	PopW r6
	PopW r4
	PopW r3
	PopW r2
	rts

;---------------------------------------------------------------
; ResetColors65
;
; Fills the colour RAM of the whole screen with screencolors
; (DKGREY on LTGREY if screencolors is still 0). Called by
; InitVideoMode after colorBase and the screen size are set.
; Destroyed: a, x, y
;---------------------------------------------------------------
ResetColors65:
	lda screencolors
	bne @1
	lda #(DKGREY << 4) + LTGREY
@1:	sta colorVal
	PushW r5
	PushW r6
	lda #0
	sta colorCX
	sta colorCY
	ldx screenCardsX
	dex
	stx colorW
	lda scrFullCardsX+1	; full cards in y
	sta colorRows
	jsr FillCards
	PopW r6
	PopW r5
	rts

;---------------------------------------------------------------
; FillCards: fill colorRows rows of colorW+1 cards, starting at
; colorCX/colorCY, with colorVal. Destroyed: a, x, r5, r6
;---------------------------------------------------------------
FillCards:
	jsr CardAddr
	phz
@row:	ldz colorW
	lda colorVal
@col:	eom
	sta (r5),z
	dez
	bpl @col		; colorW < 128 (max. 89)
	lda r5L
	clc
	adc screenCardsX
	sta r5L
	bcc @1
	inc r5H
	bne @1
	inc r6L
@1:	dec colorRows
	bne @row
	plz
	rts

;---------------------------------------------------------------
; GetCard: x = zero page address of an x coordinate word (y bits
; 8-11 in the upper nibble of its high byte), a = y low byte.
; Return: colorCX = card column, colorCY = card row
;---------------------------------------------------------------
GetCard:
	sta colorCY
	lda zpage+1,x
	lsr
	lsr
	lsr
	lsr			; y bits 8-11
	lsr
	ror colorCY
	lsr
	ror colorCY
	lsr
	ror colorCY		; colorCY = y / 8
	lda zpage+1,x
	and #$0F
	sta colorCX
	lda zpage,x
	lsr colorCX
	ror
	lsr colorCX
	ror
	lsr colorCX
	ror
	sta colorCX		; colorCX = x / 8
	rts

;---------------------------------------------------------------
; CardAddr: r5/r6 = 32 bit pointer to the colour byte of card
; colorCX/colorCY. Destroyed: a, x
;---------------------------------------------------------------
CardAddr:
	lda colorCX
	sta r5L
	lda #0
	sta r5H
	ldx colorCY
	beq @2
@1:	lda r5L
	clc
	adc screenCardsX
	sta r5L
	bcc @3
	inc r5H
@3:	dex
	bne @1
@2:	clc
	lda colorBase
	adc r5L
	sta r5L
	lda colorBase+1
	adc r5H
	sta r5H
	lda colorBase+2
	adc #0
	sta r6L
	lda colorBase+3
	adc #0
	sta r6H
	rts
