; VICINFO - shows the current VIC-IV setup and the kernal's view of it
;
; Line 1: GEOS: graphMode, screenCardsX, rows (scrFullCardsX+1),
;         screenMaxX, screenMaxY
; Line 2: VIC: $D011 $D016 $D018 $D030 $D031 $D054 $D05D $D058 $D059
;         $D05E $D07B
; Line 3: SCR ($D060-$D063, card colours), CHR ($D068-$D06A, bitmap),
;         top/bottom border ($D048/9, $D04A/B)
; Line 4: card colours read back with ColorCard at x=0 for card rows
;         0, 10, 20, ... (what the kernal believes is in colour RAM)
; Line 5: the same, read directly from the address in $D060-$D063
;         (what the VIC really displays)
; Only the text area at the top is changed. Click or key = desktop.

.include "const.inc"
.include "geossym.inc"
.include "geossym2.inc"
.include "geosmac.inc"

.setcpu "4510"

.export __STARTUP_RUN__

LINE_H	= 9
screenCardsX = $886C	; kernal variable (kernal/vars/vars.s), not in geossym.inc

.segment "STARTUP"

__STARTUP_RUN__:
	; --- read the VIC registers first, before we draw anything
	PushB CPU_DATA
	LoadB CPU_DATA, IO_IN
	lda #$47		; VIC-IV register set visible
	sta $D02F
	lda #$53
	sta $D02F
	ldx #0
@reg:	ldy regList,x
	lda $D000,y
	sta regVal,x
	inx
	cpx #REG_COUNT
	bne @reg
	PopB CPU_DATA

	; --- colour bytes, read through the kernal (ColorCard)
	LoadB rowNo, 0
	ldx #0
@cc:	stx idx
	LoadW r3, 0
	lda rowNo		; y = row * 8, bits 8-11 into r3H
	sta r11L
	lda #0
	asl r11L
	rol
	asl r11L
	rol
	asl r11L
	rol
	asl
	asl
	asl
	asl
	sta r3H
	clc
	jsr ColorCard
	ldx idx
	sta kernCol,x
	; same card read directly via $D060-$D063 + row * screenCardsX
	jsr DirectAddr
	ldz #0
	eom
	lda (r12),z
	ldx idx
	sta vicCol,x
	AddVB 10, rowNo
	inx
	cpx #8
	bne @cc

	; --- text area: black on light grey, cleared
	LoadB r2L, 0
	LoadB r2H, 5*LINE_H+4
	LoadW r3, 0
	MoveW screenMaxX, r4
	lda #(BLACK << 4) + LTGREY
	jsr ColorRectangle
	lda #0
	jsr SetPattern
	jsr Rectangle
	jsr UseSystemFont

	; line 1: GEOS
	jsr BufStart
	LoadW r0, txtGeos
	jsr BufStr
	lda graphMode
	jsr BufHexSp
	LoadW r0, txtCards
	jsr BufStr
	lda screenCardsX
	jsr BufHexSp
	LoadW r0, txtRows
	jsr BufStr
	lda scrFullCardsX+1
	jsr BufHexSp
	LoadW r0, txtMax
	jsr BufStr
	lda screenMaxX+1
	jsr BufHex
	lda screenMaxX
	jsr BufHexSp
	lda screenMaxY+1
	jsr BufHex
	lda screenMaxY
	jsr BufHexSp
	lda #1
	jsr PrintLine

	; line 2: VIC control registers
	jsr BufStart
	LoadW r0, txtVic
	jsr BufStr
	ldx #0
@l2:	stx idx
	lda regVal,x
	jsr BufHexSp
	ldx idx
	inx
	cpx #11
	bne @l2
	lda #2
	jsr PrintLine

	; line 3: pointers and borders
	jsr BufStart
	LoadW r0, txtScr
	jsr BufStr
	ldx #14			; $D063 .. $D060
@l3:	stx idx
	lda regVal,x
	jsr BufHex
	ldx idx
	dex
	cpx #10
	bne @l3
	LoadW r0, txtChr
	jsr BufStr
	ldx #17			; $D06A .. $D068
@l3b:	stx idx
	lda regVal,x
	jsr BufHex
	ldx idx
	dex
	cpx #14
	bne @l3b
	LoadW r0, txtBrd
	jsr BufStr
	lda regVal+19		; $D049
	jsr BufHex
	lda regVal+18		; $D048
	jsr BufHexSp
	lda regVal+21		; $D04B
	jsr BufHex
	lda regVal+20		; $D04A
	jsr BufHexSp
	lda #3
	jsr PrintLine

	; line 4/5: colour bytes
	jsr BufStart
	LoadW r0, txtKern
	jsr BufStr
	ldx #0
@l4:	stx idx
	lda kernCol,x
	jsr BufHexSp
	ldx idx
	inx
	cpx #8
	bne @l4
	lda #4
	jsr PrintLine
	jsr BufStart
	LoadW r0, txtVicC
	jsr BufStr
	ldx #0
@l5:	stx idx
	lda vicCol,x
	jsr BufHexSp
	ldx idx
	inx
	cpx #8
	bne @l5
	lda #5
	jsr PrintLine

	LoadW otherPressVec, ExitPress
	LoadW keyVector, Exit
	clc
	jsr StartMouseMode
	rts

ExitPress:
	lda mouseData
	bmi @1
	jmp EnterDeskTop
@1:	rts
Exit:	jmp EnterDeskTop

; r12/r13 = 32 bit address $D060-$D063 + rowNo * screenCardsX
DirectAddr:
	lda regVal+11
	sta r12L
	lda regVal+12
	sta r12H
	lda regVal+13
	sta r13L
	lda regVal+14
	and #$0F
	sta r13H
	ldy rowNo
	beq @2
@1:	lda r12L
	clc
	adc screenCardsX
	sta r12L
	bcc @3
	inc r12H
	bne @3
	inc r13L
@3:	dey
	bne @1
@2:	rts

; --- text buffer helpers
BufStart:
	LoadB bufPos, 0
	rts

BufStr:				; append NULL terminated string at r0
	ldy #0
@1:	lda (r0),y
	beq @2
	jsr BufChr
	iny
	bne @1
@2:	rts

BufHexSp:
	jsr BufHex
	lda #' '
BufChr:
	ldx bufPos
	sta buf,x
	inx
	lda #0
	sta buf,x
	stx bufPos
	rts

BufHex:
	pha
	lsr
	lsr
	lsr
	lsr
	jsr @nib
	pla
	and #$0F
@nib:	tax
	lda hexDigits,x
	jmp BufChr

PrintLine:			; a = line number 1..5
	tax
	lda #0
@1:	clc
	adc #LINE_H
	dex
	bne @1
	sta r1H
	LoadW r11, 4
	LoadW r0, buf
	jmp PutString

hexDigits:	.byte "0123456789ABCDEF"

; VIC registers read (offsets from $D000)
regList:
	.byte $11, $16, $18, $30, $31, $54, $5D, $58, $59, $5E, $7B	; 0-10
	.byte $60, $61, $62, $63					; 11-14
	.byte $68, $69, $6A						; 15-17
	.byte $48, $49, $4A, $4B					; 18-21
REG_COUNT = * - regList

txtGeos:	.byte "GEOS mode ", 0
txtCards:	.byte " cardsX ", 0
txtRows:	.byte " rows ", 0
txtMax:		.byte " maxX/Y ", 0
txtVic:		.byte "VIC 11 16 18 30 31 54 5D 58 59 5E 7B: ", 0
txtScr:		.byte "SCR $", 0
txtChr:		.byte "  CHR $", 0
txtBrd:		.byte "  border top/bottom ", 0
txtKern:	.byte "colours (ColorCard) rows 0,10..70: ", 0
txtVicC:	.byte "colours (at SCR ptr) rows 0,10..70: ", 0

regVal:		.res 22, 0
kernCol:	.res 8, 0
vicCol:		.res 8, 0
rowNo:		.byte 0
idx:		.byte 0
bufPos:		.byte 0
buf:		.res 80, 0
