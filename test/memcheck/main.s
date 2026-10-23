; MEMCHECK - hardware check for the task switcher (stage 0)
;
; Checks with 32 bit flat accesses (original contents are restored):
;   - attic RAM at the planned task slot area $8400000-$85FFFFF
;   - background buffer area $1C000 and its end in 640x400/720x569 modes,
;     which reaches into the C65 ROM area $20000+ (write protected?)
;   - whether $1F800 mirrors the colour RAM at $FF80000
; and shows ramExpSize/sysRAMFlg. Click or key = desktop.

.include "const.inc"
.include "geossym.inc"
.include "geossym2.inc"
.include "geosmac.inc"

.setcpu "4510"

.export __STARTUP_RUN__

LINE_H		= 10

.segment "STARTUP"

__STARTUP_RUN__:
	; --- run all tests first, interrupts off
	php
	sei
	ldx #0
@t:	stx testNo
	txa
	asl
	asl
	tay
	lda testAddr,y		; 32 bit address -> r12/r13
	sta r12L
	lda testAddr+1,y
	sta r12H
	lda testAddr+2,y
	sta r13L
	lda testAddr+3,y
	sta r13H
	jsr TestAddr
	ldx testNo
	sta result,x
	lda origVal
	sta resultOrig,x
	inx
	cpx #TEST_COUNT
	bne @t
	jsr TestMirror
	sta mirrorResult
	plp

	; --- output
	LoadB r2L, 0
	LoadB r2H, (TEST_COUNT + 3) * LINE_H + 4
	LoadW r3, 0
	MoveW screenMaxX, r4
	lda #(BLACK << 4) + LTGREY
	jsr ColorRectangle
	lda #0
	jsr SetPattern
	jsr Rectangle
	jsr UseSystemFont

	jsr BufStart
	LoadW r0, txtHead
	jsr BufStr
	lda ramExpSize
	jsr BufHexSp
	LoadW r0, txtFlg
	jsr BufStr
	lda sysRAMFlg
	jsr BufHex
	lda #1
	jsr PrintLine

	ldx #0
@out:	stx testNo
	jsr BufStart
	lda testNo		; label
	asl
	tax
	lda testLabel,x
	sta r0L
	lda testLabel+1,x
	sta r0H
	jsr BufStr
	ldx testNo
	lda result,x
	asl
	tax
	lda resultText,x
	sta r0L
	lda resultText+1,x
	sta r0H
	jsr BufStr
	LoadW r0, txtOrig
	jsr BufStr
	ldx testNo
	lda resultOrig,x
	jsr BufHex
	lda testNo
	clc
	adc #2
	jsr PrintLine
	ldx testNo
	inx
	cpx #TEST_COUNT
	bne @out

	jsr BufStart
	LoadW r0, txtMirror
	jsr BufStr
	LoadW r0, txtYes
	lda mirrorResult
	bne @m
	LoadW r0, txtNo
@m:	jsr BufStr
	lda #TEST_COUNT + 2
	jsr PrintLine

	jsr BufStart
	LoadW r0, txtExit
	jsr BufStr
	lda #TEST_COUNT + 3
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

;---------------------------------------------------------------
; TestAddr: r12/r13 = 32 bit address
; Return: a = 0 read/write OK, 1 read-only (write ignored),
;         2 error (value changed but not to what was written)
;---------------------------------------------------------------
TestAddr:
	ldz #0
	eom
	lda (r12),z
	sta origVal
	lda #$A5
	eom
	sta (r12),z
	eom
	lda (r12),z
	cmp #$A5
	bne @notWritten
	lda #$5A
	eom
	sta (r12),z
	eom
	lda (r12),z
	cmp #$5A
	bne @err
	jsr Restore
	lda #0
	rts
@notWritten:
	cmp origVal
	bne @err
	jsr Restore
	lda #1
	rts
@err:	jsr Restore
	lda #2
	rts

Restore:
	lda origVal
	eom
	sta (r12),z
	rts

;---------------------------------------------------------------
; TestMirror: does a write to $1F800 show up in colour RAM $FF80000?
; Return: a = 1 yes, 0 no
;---------------------------------------------------------------
TestMirror:
	LoadW r12, $F800
	LoadW r13, $0001
	LoadW r14, $0000
	LoadW r15, $0FF8
	ldz #0
	eom
	lda (r14),z
	sta colOrig
	eom
	lda (r12),z
	sta origVal
	eor #$FF
	eom
	sta (r12),z
	eom
	lda (r14),z
	pha
	jsr Restore		; restores $1F800 (and colour RAM if mirrored)
	pla
	cmp colOrig
	beq @no
	lda #1
	rts
@no:	lda #0
	rts

; --- text buffer helpers (as in VICINFO)
BufStart:
	LoadB bufPos, 0
	rts

BufStr:
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

PrintLine:			; a = line number 1..
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

testAddr:
	.dword $08400000	; attic RAM, first task slot
	.dword $085FFFFF	; attic RAM, end of slot 8
	.dword $0001C000	; background buffer start
	.dword $0001FE7F	; background buffer end, 640x200
	.dword $00020000	; C65 ROM area, used by 640x400/720 buffer
	.dword $00023CFF	; background buffer end, 640x400
	.dword $0002880A	; background buffer end, 720x569
TEST_COUNT = (* - testAddr) / 4

testLabel:
	.word l0, l1, l2, l3, l4, l5, l6
l0:	.byte "Attic $8400000 (slot 1):   ", 0
l1:	.byte "Attic $85FFFFF (slot 8 end): ", 0
l2:	.byte "Back buffer $1C000:        ", 0
l3:	.byte "Back buffer end $1FE7F (640x200): ", 0
l4:	.byte "ROM area $20000:           ", 0
l5:	.byte "Back buffer end $23CFF (640x400): ", 0
l6:	.byte "Back buffer end $2880A (720x569): ", 0

resultText:	.word rOK, rRO, rErr
rOK:	.byte "OK (read/write)", 0
rRO:	.byte "READ-ONLY", 0
rErr:	.byte "ERROR", 0

txtHead:	.byte BOLDON, "MEMCHECK", PLAINTEXT, "   ramExpSize ", 0
txtFlg:		.byte " sysRAMFlg ", 0
txtOrig:	.byte "   (value ", 0
txtMirror:	.byte "$1F800 mirrors colour RAM $FF80000: ", 0
txtYes:		.byte "YES", 0
txtNo:		.byte "no", 0
txtExit:	.byte "Click or key = back to desktop", 0

testNo:		.byte 0
origVal:	.byte 0
colOrig:	.byte 0
mirrorResult:	.byte 0
result:		.res TEST_COUNT, 0
resultOrig:	.res TEST_COUNT, 0
bufPos:		.byte 0
buf:		.res 80, 0
