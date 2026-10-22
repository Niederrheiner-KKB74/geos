; GEOS KERNAL by Berkeley Softworks
; reverse engineered by Maciej Witkowiak, Michael Steil
;
; VIC initialization table

.include "const.inc"
.include "geossym.inc"
.include "geosmac.inc"
.include "config.inc"
.include "kernal.inc"
.include "c64.inc"

.global VIC_IniTbl
.global VIC_IniTbl_end

.segment "hw1a"

VIC_IniTbl:
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
.ifdef mega65
	; $D011 with display enable (bit 4) OFF. On the MEGA65 this table is
	; applied by DoFirstInitIO before InitVideoMode has set up the VIC-IV
	; bitmap/colour pointers ($D060-$D06A), so switching the bitmap on here
	; showed random memory as coloured 8x8 cells during boot.
	; InitVideoMode turns the display on again (vmiD011) - every caller of
	; DoFirstInitIO is followed by SetNewMode.
	.byte $00, $2b, $fb, $aa, $aa, $01, $08, $00
.else
	.byte $00, $3b, $fb, $aa, $aa, $01, $08, $00
.endif
	.byte $00, $0f, $01, $00, $00, $00
VIC_IniTbl_end:

