; Kind of C65 GEOS "loader" / basic stub / decruncher.
;
; (C)2016 LGB Gábor Lénárt

;.INCLUDE "c65.inc"

.include "const.inc"
.include "geossym.inc"

.SETCPU "4510"

.SEGMENT "LOADADDR"
	.IMPORT __STUB_LOAD__
	.WORD __STUB_LOAD__


.SEGMENT "STUB"
.SCOPE
	.WORD	next
	.WORD	2016
	.BYTE	$FE, $02        ; BASIC token (double byte ...) for "BANK"
	.BYTE	" 0 : "
	.BYTE	$9E, " "	; SYS token
	.BYTE	<(main/10000+48)
	.BYTE	<(main/1000 .MOD 10+48)
	.BYTE	<(main/100 .MOD 10+48)
	.BYTE	<(main/10 .MOD 10+48)
	.BYTE	<(main .MOD 10+48)
	.BYTE	" : GEOS LOADER AND KERNAL FOR C65 MODE ONLY"
	.BYTE	0
next:	.WORD	0
.ENDSCOPE



.CODE
.PROC main

	SEI
	CLD
	LDA	#0
	TAX
	TAY
	TAZ	; we use Z register as zero, so STZ is about the same as on 65C02
	MAP	; no CPU mapping
	TAB	; just to be sure: ZP at $0000
	INY
	TYS	; just to be sure: stack at $100
	SEE	; just to be sure: 8 bit stack
	EOM

.if 0
	; 10113/10114 clear device numbers of the f011 drive, we will
	; manage those independent of dos
	lda	#$10
	sta 	$02
	lda 	#$01
	sta 	$03
	lda 	#$01
	sta 	$04
	lda	#$00
	sta 	$05

	lda	#$18
	LDZ	#3
	EOM
	sta 	($02), Z
	lda 	#$19
	INZ
	EOM
	sta 	($02), Z
.endif
	; Just to be sure, enable newVic mode, to access eg VIC-3 register $30
	; We don't need Mega65 fast mode here at any price, let's do that
	; later maybe, in c65/start.s
	; CPU port stuff
	LDA	#$2F
	STA	0
	LDA	#$37
	STA	1

	LDA	#C65_VIC_INIT1
	STA	$D02F
	LDA	#C65_VIC_INIT2
	STA	$D02F

	LDA	#C65_VIC_INIT1
	STA	$D02F
	LDA	#C65_VIC_INIT2
	STA	$D02F

	; Blank the display while we move the screen/charset pointers away
	; from the BASIC text screen (see $D060/$D068 below) and while the
	; kernal boots. Otherwise random memory shows up as coloured 8x8
	; cells. InitVideoMode in the kernal switches the display on again.
	LDA	$D011
	AND	#%11101111
	STA	$D011

	; Various VIC register stuffs
	STZ	$D030	; turn ROM mappings / etc OFF
	STZ	$D031
	STZ	$D019	; disable VIC interrupts
	STZ	$D01A

; not working with xemu
; disable badline emulation
	LDA	#$04
	sta	$D710
	lda	$D05D
	; bit 6: raster delay off; bit 7: VIC-II "hot registers" off.
	; With hot registers on, every write to $D011/$D016/$D018/$D031
	; (e.g. VIC_IniTbl in DoFirstInitIO) recalculates the VIC-IV screen
	; and charset pointers from the VIC-II registers and throws away the
	; pointers set below. InitVideoMode switches them on only briefly.
	and	#%00111111
	;ora	#%01000000
	sta	$D05D

	LDA   	$D054	;40 mhz
	ORA   	#$40
	STA   	$D054
	lda   	#$40
	sta	$d031

  ; force 1351 emulation
	;lda	#5
	;sta	$D61B

	; Prepare what the VIC shows until the kernal has set up the GEOS
	; video mode (InitVideoMode): clear the GEOS bitmap in bank 4
	; ($40000-$4DFFF) and fill the card colour RAM ($4E000-$4FFFF) with
	; DKGREY on LTGREY by DMA, then point the VIC-IV screen and charset/
	; bitmap pointers there. The old pointers ($12000/$14000) showed
	; random memory as coloured 8x8 cells during boot; switching the
	; display off with $D011 alone did not hide that on the MEGA65.
	LDA	#0
	STA	$D702		; DMA list in bank 0
	STA	$D704		; ... MB 0
	LDA	#>dmaClearBitmap
	STA	$D701
	LDA	#<dmaClearBitmap
	STA	$D705		; start enhanced DMA job
	LDA	#>dmaFillColour
	STA	$D701
	LDA	#<dmaFillColour
	STA	$D705

	LDA	#<$E000		; screen pointer (card colours): $4E000
	STA	$D060
	LDA	#>$E000
	STA	$D061
	LDA	#4
	STA	$D062
	LDA	#0
	STA	$D063
	LDA	#<$0000		; charset/bitmap pointer: $40000
	STA	$D068
	LDA	#>$0000
	STA	$D069
	LDA	#4
	STA	$D06A

	LDA	#$30	; full RAM for uncrunching
	STA	1
	.IMPORT	uncruncher
	JSR	uncruncher
	;STZ	53280
	;STZ	53281

	JMP	$5000

; F018A DMA jobs (enhanced option list, then 11 byte job)
dmaClearBitmap:
	.BYTE	$0A		; F018A list format
	.BYTE	$81, $00	; destination MB 0
	.BYTE	$00		; end of options
	.BYTE	$03		; fill
	.WORD	$E000		; count
	.WORD	$0000		; fill value (low byte)
	.BYTE	$00
	.WORD	$0000		; destination
	.BYTE	$04		; destination bank 4
	.WORD	$0000		; modulo
dmaFillColour:
	.BYTE	$0A
	.BYTE	$81, $00
	.BYTE	$00
	.BYTE	$03		; fill
	.WORD	$2000		; count
	.WORD	(DKGREY << 4) + LTGREY
	.BYTE	$00
	.WORD	$E000		; destination
	.BYTE	$04		; destination bank 4
	.WORD	$0000

;	========================
.ENDPROC



.SEGMENT "GEOS"
.INCBIN "build/mega65/compressed.bin"
