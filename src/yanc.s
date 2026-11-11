;=====================================================================
;  YANC.SYSTEM - Yet Another Norton Commander, v1.2
;               Norton Commander style file manager
;               for the Apple IIc (65C02), 80 columns, ProDOS 8
;
;  Two panels, function-key style command bar (keys 1..0),
;  MouseText frames.  Disk/volume operations only:
;  browse, view (text/hex), copy, rename/move, mkdir, delete.
;
;  Assemble:  ca65 --cpu 65C02 yanc.s  &&  ld65 -C yanc.cfg yanc.o -o YANC.SYSTEM
;  ProDOS file type $FF (SYS), aux type $2000
;=====================================================================

        .setcpu "65C02"

;--------------------------------------------------------------------
; Hardware / ProDOS
;--------------------------------------------------------------------
MLI         = $BF00
KBD         = $C000
KBDSTRB     = $C010
SET80STORE  = $C001
SET80COL    = $C00D
SETALTCHR   = $C00F
TXTSET      = $C051
MIXCLR      = $C052
TXTPAGE1    = $C054
TXTPAGE2    = $C055
OAPPLE      = $C061

P_CREATE    = $C0
P_DESTROY   = $C1
P_RENAME    = $C2
P_SETINFO   = $C3
P_GETINFO   = $C4
P_ONLINE    = $C5
P_GETPFX    = $C7
P_SETPFX    = $C6
LOADER      = $1000
LDIOBUF     = $1C00
P_OPEN      = $C8
P_READ      = $CA
P_WRITE     = $CB
P_CLOSE     = $CC
P_SETMARK   = $CE
P_RDBLK     = $80
P_WRBLK     = $81
BUFA        = $8000
BUFB        = $8200
P_QUIT      = $65

;--------------------------------------------------------------------
; Memory map
;   $0800-$0FFF  BSS (variables, buffers)
;   $1000-$12FF  program loader (copied there when launching)
;   $1400-$17FF  ProDOS I/O buffer 2
;   $1800-$19FF  directory block buffer
;   $2000-$5BFF  code + data
;   $5C00-$6BFF  left panel entries  (128 x 32 bytes)
;   $6C00-$7BFF  right panel entries
;   $7C00-$7FFF  ProDOS I/O buffer 1
;   $8000-$BBFF  copy / view buffer
;--------------------------------------------------------------------
ENTA_HI     = $5C
ENTB_HI     = $6C
IOBUF1      = $7C00
IOBUF2      = $1400
DIRBLK      = $1800
COPYBUF     = $8000
COPYLEN     = $3C00
VIEWLEN     = $0800

MAXENT      = 128
NROWS       = 17            ; file rows per panel
FROW        = 2             ; first file row on screen

; entry layout (32 bytes)
E_LEN       = 0             ; name length
E_TYPE      = 16
E_STOR      = 17            ; storage type ($FF = ".." pseudo entry)
E_BLKS      = 18
E_EOF       = 20
E_AUX       = 23
E_MDATE     = 25
E_ACC       = 29
E_TAG       = 30

; custom error codes
ERR_SAME    = $E1
ERR_NOTDIR  = $E2
ERR_ONE     = $E3
ERR_NOTEMPTY= $E4
ERR_LONG    = $E5
ERR_NOVOL   = $E6
ERR_NOBS    = $E7
ERR_BOOT    = $E8
ERR_KFOLDER = $E9
ERR_KDST    = $EA
ERR_KMOUNT  = $EB
ERR_KPROT   = $EC

;--------------------------------------------------------------------
; Macros
;--------------------------------------------------------------------

.macro JCS l
        bcc :+
        jmp l
:
.endmacro
.macro JCC l
        bcs :+
        jmp l
:
.endmacro
.macro JNE l
        beq :+
        jmp l
:
.endmacro

.import __LOADER_LOAD__, __LOADER_RUN__, __LOADER_SIZE__

.macro MLICALL cmd, parms
        jsr MLI
        .byte cmd
        .word parms
.endmacro

.macro PRINT str
        lda #<(str)
        ldy #>(str)
        jsr puts
.endmacro

.macro GOTO xx, yy
        ldx #xx
        ldy #yy
        jsr gotoxy
.endmacro

.macro SETPTR zp, addr
        lda #<(addr)
        sta zp
        lda #>(addr)
        sta zp+1
.endmacro

;--------------------------------------------------------------------
; Zero page
;--------------------------------------------------------------------
        .zeropage
ptr:    .res 2
ptr2:   .res 2
ep:     .res 2
ep2:    .res 2
scrp:   .res 2
sptr:   .res 2
vp:     .res 2
vendp:  .res 2
ttl:    .res 2
cx:     .res 1
cy:     .res 1
attr:   .res 1          ; 0 normal, $80 inverse, $40 MouseText
tmp:    .res 1
tmp2:   .res 1
pn:     .res 1          ; panel being worked on
px:     .res 1          ; its left column
num:    .res 3
key:    .res 1
oakey:  .res 1
row:    .res 1
frow:   .res 1
fidx:   .res 1
sattr:  .res 1
tlen:   .res 1
tstart: .res 1
tshow:  .res 1
dtmp:   .res 1
sn:     .res 1
si:     .res 1
sj:     .res 1
skey:   .res 1
ib:     .res 1
sel_l:  .res 1
cnt:    .res 1
bl:     .res 1
br:     .res 1
bt:     .res 1
bb:     .res 1
bw:     .res 1

;--------------------------------------------------------------------
; BSS
;--------------------------------------------------------------------
        .bss
path0:  .res 65
path1:  .res 65
fp1:    .res 65
fp2:    .res 65
dstdir: .res 65
inbuf:  .res 65
pfxbuf: .res 65
vbuf:   .res 17
selname:.res 16
tmpname:.res 16
numbuf: .res 8
vl:     .res 16
idxtab: .res 256
onbuf:  .res 256
mk0:    .res 256
mk1:    .res 256
mk2:    .res 256
pcount: .res 2
ptop:   .res 2
pcur:   .res 2
pntag:  .res 2
pfreel: .res 2
pfreeh: .res 2
ptotl:  .res 2
ptoth:  .res 2
cp:     .res 1          ; active panel
sortmode:.res 1
nsel:   .res 1
nskip:  .res 1
moveflag:.res 1
allflag:.res 1
seltype:.res 1
errcode:.res 1
vn:     .res 1
vsel:   .res 1
vpage:  .res 1
vendf:  .res 1
hexmode:.res 1
lastcr: .res 1
vnext:  .res 3
vaddr:  .res 3
oldcur: .res 1
startdir:.res 65
lmode:  .res 1
lockmode:.res 1
curblk: .res 2
firstblk:.res 2
firstoff:.res 2
tgtoff: .res 2
oldtop: .res 1
xpath:  .res 2          ; extended files (see "Extended files")
extkey: .res 2
srcunit:.res 1
fork:   .res 1
tkeyl:  .res 2
tkeyh:  .res 2
tmade:  .res 2
dirkey: .res 2
pidx:   .res 1
plen1:  .res 1
fhdr:   .res 8
bidx:   .res 2
kegs:   .res 1          ; 1 = running in KEGS (see "KEGS disk images")
kprot:  .res 1          ; drive YANC runs from (slot*16 + drive)
pmode:  .res 2          ; per panel: 0 ProDOS, 1 KEGS disk images
ksel:   .res 1
knopt:  .res 1          ; number of drives in the insert box
kopt:   .res 6          ; their DRIVES entry numbers

;====================================================================
        .code
;====================================================================
start:
        cld
        ; clear BSS ($0800-$0FFF)
        lda #$08
        sta ptr+1
        stz ptr
        ldx #8
        lda #0
        tay
@z:     sta (ptr),y
        iny
        bne @z
        inc ptr+1
        dex
        bne @z

        sta SET80COL
        sta SET80STORE
        sta SETALTCHR
        sta TXTSET
        sta MIXCLR
        sta TXTPAGE1
        jsr cls

        jsr scanvols
        ; left panel = current prefix
        MLICALL P_GETPFX, pfxp
        bcs @nopfx
        lda pfxbuf
        cmp #2
        bcc @nopfx
        tax
        dex                     ; drop trailing '/'
        stx path0
@cpy:   lda pfxbuf,x
        sta path0,x
        dex
        bne @cpy
        bra @right
@nopfx: lda vn
        bne :+
        lda #ERR_NOVOL
        jsr showerr
        jmp quitnow
:       stz pn
        ldy vl
        jsr setvol
@right: ; remember start directory (to find BASIC.SYSTEM later)
        ldx #64
:       lda path0,x
        sta startdir,x
        dex
        bpl :-
        jsr kdetect             ; running in KEGS?
        ; right panel = first other volume
        stz pn
        jsr getvolname
        ldx #0
@rv:    cpx vn
        beq @rsame
        ldy vl,x
        jsr cmpvol
        bne @rfound
        inx
        bra @rv
@rfound:
        ldy vl,x
        lda #1
        sta pn
        jsr setvol
        bra @load
@rsame: ldx #64
:       lda path0,x
        sta path1,x
        dex
        bpl :-
@load:  stz pn
        jsr loaddir
        lda #1
        sta pn
        jsr loaddir
        jmp main_redraw

;====================================================================
; Main loop
;====================================================================
main_redraw:
        jsr drawall
main_key:
        lda cp
        sta pn
        jsr setpx
        jsr getkey
        ldx pn
        lda pcur,x
        sta oldcur
        lda ptop,x
        sta oldtop
        jsr iskegs
        beq :+
        jmp kmain_key           ; KEGS disk images panel
:       ldy #0
@l:     lda keytab,y
        beq @other
        cmp key
        beq @hit
        iny
        bra @l
@hit:   tya
        asl a
        tax
        jmp (jmptab,x)
@other: lda key
        cmp #'a'
        bcc @u
        cmp #'z'+1
        bcs @u
        and #$DF
@u:     cmp #'A'
        bcc main_key
        cmp #'Z'+1
        bcs main_key
        sta key
        jmp k_search

keytab: .byte $0A,$0B,$08,$15,$09,$0D,$1B,$7F,' ','+','-','*'
        .byte '1','2','3','5','6','7','8','9','0',$12,$13,'4',0
jmptab: .word k_down,k_up,k_pgup,k_pgdn,k_tab,k_enter,k_parent,k_parent
        .word k_tag,k_tagall,k_untagall,k_invert
        .word k_help,k_vol,k_view,k_copy,k_move,k_mkdir,k_delete,k_sort
        .word k_quit,k_reread,k_swap,k_lock

;--------------------------------------------------------------------
; Cursor movement
;--------------------------------------------------------------------
k_down: lda oakey
        bmi k_end
        ldx pn
        lda pcur,x
        inc a
        cmp pcount,x
        bcs nomove
        sta pcur,x
        jmp movedone
k_up:   lda oakey
        bmi k_home
        ldx pn
        lda pcur,x
        beq nomove
        dec a
        sta pcur,x
        jmp movedone
k_home: ldx pn
        stz pcur,x
        jmp movedone
k_end:  ldx pn
        lda pcount,x
        beq nomove
        dec a
        sta pcur,x
        jmp movedone
nomove: jmp main_key
k_pgdn: ldx pn
        lda pcount,x
        beq nomove
        lda pcur,x
        clc
        adc #NROWS-1
        cmp pcount,x
        bcc :+
        lda pcount,x
        dec a
:       sta pcur,x
        jmp movedone
k_pgup: ldx pn
        lda pcur,x
        sec
        sbc #NROWS-1
        bcs :+
        lda #0
:       sta pcur,x
movedone:
        jsr fixtop
        ldx pn
        lda ptop,x
        cmp oldtop
        bne @all
        lda oldcur              ; redraw only old and new cursor rows
        jsr drawone
        ldx pn
        lda pcur,x
        jsr drawone
        bra @info
@all:   jsr drawfiles
@info:  jsr drawinfo
        jmp main_key

; redraw list row showing logical index A (if visible)
drawone:
        sta fidx
        ldx pn
        sec
        sbc ptop,x
        cmp #NROWS
        bcs @r
        sta frow
        jmp drawfrow
@r:     rts

k_tab:  lda cp
        eor #1
        sta cp
        jmp main_redraw

k_search:
        ldx pn
        lda pcount,x
        beq @no
        lda pcur,x
        sta cnt
        stz tmp2
@l:     inc cnt
        ldx pn
        lda cnt
        cmp pcount,x
        bcc :+
        stz cnt
        lda #0
:       jsr lentptr
        jsr firstch
        cmp key
        beq @f
        inc tmp2
        ldx pn
        lda tmp2
        cmp pcount,x
        bcc @l
@no:    jmp main_key
@f:     ldx pn
        lda cnt
        sta pcur,x
        jmp movedone

;--------------------------------------------------------------------
; Enter / parent
;--------------------------------------------------------------------
k_enter:
        ldx pn
        lda pcount,x
        beq @no
        lda pcur,x
        jsr lentptr
        ldy #E_STOR
        lda (ep),y
        cmp #$FF
        beq k_parent
        ldy #E_TYPE
        lda (ep),y
        cmp #$0F
        beq :+
        jmp runfile
:       jsr setselname
        jsr pathptr
        lda ptr
        sta ptr2
        lda ptr+1
        sta ptr2+1
        jsr catpath
        bcs @long
        jsr loaddir
        jmp main_redraw
@long:  lda #ERR_LONG
        jsr showerr
        jmp main_redraw
@no:    jmp main_key

k_parent:
        jsr pathdepth
        cmp #2
        bcc @no
        jsr pathptr
        lda (ptr)
        tay
@l:     lda (ptr),y
        cmp #'/'
        beq @f
        dey
        bra @l
@f:     sty tmp
        lda (ptr)
        sec
        sbc tmp
        sta tmpname
        ldx #0
@c:     iny
        lda (ptr),y
        sta tmpname+1,x
        inx
        cpx tmpname
        bne @c
        ldy tmp
        dey
        tya
        sta (ptr)
        jsr loaddir
        jsr findtmp
        jmp main_redraw
@no:    jmp main_key

; set cursor of panel pn on entry named tmpname
findtmp:
        stz cnt
@l:     ldx pn
        lda cnt
        cmp pcount,x
        bcs @d
        jsr lentptr
        lda (ep)
        cmp tmpname
        bne @n
        tay
@c:     lda (ep),y
        cmp tmpname,y
        bne @n
        dey
        bne @c
        ldx pn
        lda cnt
        sta pcur,x
        jmp fixtop
@n:     inc cnt
        bra @l
@d:     rts

;--------------------------------------------------------------------
; Tagging
;--------------------------------------------------------------------
k_tag:  ldx pn
        lda pcount,x
        beq @no
        lda pcur,x
        jsr lentptr
        ldy #E_STOR
        lda (ep),y
        cmp #$FF
        beq @mv
        ldy #E_TAG
        lda (ep),y
        eor #1
        sta (ep),y
        ldx pn
        cmp #0
        beq @dec
        inc pntag,x
        bra @mv
@dec:   dec pntag,x
@mv:    ldx pn
        lda pcur,x
        inc a
        cmp pcount,x
        bcs :+
        sta pcur,x
:       jmp movedone
@no:    jmp main_key

k_tagall:
        lda #1
        bra tagmode
k_untagall:
        lda #0
        bra tagmode
k_invert:
        lda #2
tagmode:
        sta tmp2
        ldx pn
        stz pntag,x
        stz cnt
@l:     ldx pn
        lda cnt
        cmp pcount,x
        bcs @d
        jsr lentptr
        ldy #E_STOR
        lda (ep),y
        cmp #$FF
        beq @n
        ldy #E_TYPE
        lda (ep),y
        cmp #$0F
        bne @f
        lda #0
        bra @st
@f:     lda tmp2
        cmp #2
        bne @st
        ldy #E_TAG
        lda (ep),y
        eor #1
@st:    ldy #E_TAG
        sta (ep),y
        cmp #0
        beq @n
        ldx pn
        inc pntag,x
@n:     inc cnt
        bra @l
@d:     jsr drawfiles
        jsr drawinfo
        jmp main_key

;--------------------------------------------------------------------
; Misc commands
;--------------------------------------------------------------------
k_sort: lda sortmode
        eor #1
        sta sortmode
        stz pn
        jsr sortpanel
        lda #1
        sta pn
        jsr sortpanel
        jmp main_redraw

k_reread:
        jsr reloadboth
        jmp main_redraw

k_swap: ldx #64
@l:     lda path0,x
        ldy path1,x
        sta path1,x
        tya
        sta path0,x
        dex
        bpl @l
        lda pmode
        ldx pmode+1
        sta pmode+1
        stx pmode
        stz pn
        jsr loaddir
        lda #1
        sta pn
        jsr loaddir
        jmp main_redraw

k_quit: jsr dlgbox_q
        GOTO 14,10
        PRINT s_quit
        GOTO 14,13
        PRINT s_yn
        jsr yesno
        bcs quitnow
        jmp main_redraw
quitnow:
        jsr cls
        stz closeref
        MLICALL P_CLOSE, closep
        MLICALL P_QUIT, quitp
        brk

k_help: lda #2
        sta bl
        lda #77
        sta br
        lda #1
        sta bt
        lda #22
        sta bb
        lda #<t_help
        ldy #>t_help
        jsr box
        lda #3
        sta row
        ldx #0
@l:     lda helptab,x
        sta sptr
        lda helptab+1,x
        sta sptr+1
        ora sptr
        beq @w
        phx
        ldx #5
        ldy row
        jsr gotoxy
        lda sptr
        ldy sptr+1
        jsr puts
        plx
        inx
        inx
        inc row
        bra @l
@w:     jsr getkey
        jmp main_redraw

;--------------------------------------------------------------------
; Volume selection (2)
;--------------------------------------------------------------------
k_vol:  jsr scanvols
        lda vn
        bne :+
        lda #ERR_NOVOL
        jsr showerr
        jmp main_redraw
:       stz vsel
        lda #20
        sta bl
        lda #59
        sta br
        lda #4
        sta bt
        lda vn
        clc
        adc #7
        ldx kegs
        beq :+
        adc #2                  ; + "KEGS disk images..."
:       sta bb
        lda #<t_vol
        ldy #>t_vol
        jsr box
@draw:  ldx #0
@e:     cpx vn
        beq @kitem
        phx
        txa
        clc
        adc #6
        tay
        ldx #22
        jsr gotoxy
        plx
        stz attr
        cpx vsel
        bne :+
        lda #$80
        sta attr
:       ldy vl,x
        lda #' '
        jsr putc
        lda #'S'
        jsr putc
        lda onbuf,y
        lsr a
        lsr a
        lsr a
        lsr a
        and #7
        ora #'0'
        jsr putc
        lda #','
        jsr putc
        lda #'D'
        jsr putc
        lda onbuf,y
        asl a
        lda #'1'
        adc #0
        jsr putc
        lda #' '
        jsr putc
        jsr putc
        lda #'/'
        jsr putc
        lda onbuf,y
        and #$0F
        sta tmp
@n:     lda onbuf+1,y
        jsr putc
        iny
        dec tmp
        bne @n
@p:     lda cx
        cmp #58
        bcs :+
        lda #' '
        jsr putc
        bra @p
:       stz attr
        inx
        bra @e
@kitem: lda kegs
        beq @k
        lda vn
        clc
        adc #7
        tay
        ldx #22
        jsr gotoxy
        stz attr
        lda vsel
        cmp vn
        bne :+
        lda #$80
        sta attr
:       PRINT s_kitem
@kp:    lda cx
        cmp #58
        bcs :+
        lda #' '
        jsr putc
        bra @kp
:       stz attr
@k:     jsr getkey
        cmp #$0A
        beq @dn
        cmp #$15
        beq @dn
        cmp #$0B
        beq @up
        cmp #$08
        beq @up
        cmp #$0D
        beq @ch
        cmp #$1B
        bne @k
        jmp main_redraw
@dn:    lda vsel
        inc a
        cmp vn
        bcc @dnok
        bne @k
        ldx kegs                ; one more row: KEGS disk images
        beq @k
@dnok:  sta vsel
        jmp @draw
@up:    lda vsel
        beq @k
        dec vsel
        jmp @draw
@ch:    lda cp
        sta pn
        tax
        lda vsel
        cmp vn
        bne @chv
        lda #1                  ; KEGS disk images
        sta pmode,x
        jsr kroot
        jsr loaddir
        jmp main_redraw
@chv:   stz pmode,x
        ldx vsel
        ldy vl,x
        jsr setvol
        jsr loaddir
        jmp main_redraw

;--------------------------------------------------------------------
; Copy (5)
;--------------------------------------------------------------------
k_copy: stz moveflag
        jsr kchkdst
        jsr selcount
        lda nsel
        bne :+
        jmp main_key
:       jsr otherpath_to_dst
        jsr samedir
        bne :+
        lda #ERR_SAME
        jsr showerr
        jmp main_redraw
:       lda #<t_copy
        ldy #>t_copy
        jsr dlgbox
        GOTO 14,9
        PRINT s_copy
        lda nsel
        jsr prdec
        PRINT s_itemsto
        GOTO 14,11
        SETPTR ptr, dstdir
        lda #52
        jsr pstr
        GOTO 14,13
        PRINT s_yn
        jsr yesno
        bcs :+
        jmp main_redraw
:       jsr copyloop
        jsr reloadboth
        jmp main_redraw

otherpath_to_dst:
        lda cp
        eor #1
        sta pn
        jsr pathptr
        lda cp
        sta pn
ptr_to_dstdir:
        lda (ptr)
        tay
@l:     lda (ptr),y
        sta dstdir,y
        dey
        bpl @l
        rts

; Z=1 if path of pn equals dstdir
samedir:
        jsr pathptr
        lda (ptr)
        cmp dstdir
        bne @r
        tay
@l:     lda (ptr),y
        cmp dstdir,y
        bne @r
        dey
        bne @l
@r:     rts

; copy (or move) all selected files of panel pn into dstdir
copyloop:
        stz allflag
        stz nskip
        jsr selinit
@l:     jsr selnext
        bcs @end
        lda seltype
        cmp #$0F
        bne @f
        inc nskip
        bra @l
@f:     jsr copyone
        bcs @abort
        cmp #0
        bne @l                  ; skipped
        lda moveflag
        beq @l
        SETPTR despath, fp1
        jsr destroy
        bcc @l
        jsr showerr
@abort:
@end:   lda nskip
        beq @r
        lda #<t_note
        ldy #>t_note
        jsr dlgbox
        GOTO 14,10
        lda nskip
        jsr prdec
        PRINT s_skipped
        GOTO 14,13
        PRINT s_anykey
        jsr getkey
@r:     rts

; copy selname from path(pn) to dstdir
; returns C=1 abort, else A=0 copied / A=1 skipped
copyone:
        jsr pathptr
        SETPTR ptr2, fp1
        jsr catpath
        JCS @long
        SETPTR ptr, dstdir
        SETPTR ptr2, fp2
        jsr catpath
        JCS @long
        lda #<t_copy
        ldy #>t_copy
        ldx moveflag
        beq :+
        lda #<t_renmov
        ldy #>t_renmov
:       jsr dlgbox
        GOTO 14,9
        PRINT s_copying
        SETPTR ptr, selname
        lda #15
        jsr pstr
        SETPTR gfipath, fp1
        MLICALL P_GETINFO, gfip
        JCS @err0
        lda gfitype
        sta crtype
        lda gfiaux
        sta craux
        lda gfiaux+1
        sta craux+1
        lda gficd
        sta crcd
        lda gficd+1
        sta crcd+1
        lda gfict
        sta crct
        lda gfict+1
        sta crct+1
        lda #$C3
        sta cracc
        lda #1
        sta crstyp
        SETPTR crpath, fp2
@cre:   MLICALL P_CREATE, crp
        bcc @open
        cmp #$47
        JNE @err0
        lda allflag
        bne @ovr
        GOTO 14,11
        PRINT s_exists
        GOTO 14,13
        PRINT s_ovr
@ask:   jsr getkey
        and #$DF
        cmp #'Y'
        beq @ovr
        cmp #'A'
        beq @all
        cmp #'N'
        beq @skip
        cmp #$1B
        bne @ask
        sec
        rts
@skip:  lda #1
        clc
        rts
@all:   inc allflag
@ovr:   SETPTR despath, fp2
        jsr destroy
        JCS @err0
        bra @cre
@long:  lda #ERR_LONG
        jmp @err0
@open:  lda gfistyp
        cmp #5
        bne @std
        jsr cpext               ; extended (forked) file
        JCS @errd
        jmp @ok
@std:   SETPTR openpath, fp1
        SETPTR openbuf, IOBUF1
        MLICALL P_OPEN, openp
        bcs @errd
        MLICALL P_OPEN, open2p
        bcs @errc
        lda openref
        sta readref
        lda open2ref
        sta writeref
@rd:    SETPTR readbuf, COPYBUF
        SETPTR readreq, COPYLEN
        MLICALL P_READ, readp
        bcs @rerr
        lda readtrn
        sta writereq
        lda readtrn+1
        sta writereq+1
        MLICALL P_WRITE, writep
        bcs @errc
        bra @rd
@rerr:  cmp #$4C
        bne @errc
        stz closeref
        MLICALL P_CLOSE, closep
        bcs @errd
        SETPTR sfipath, fp2
        jsr gfi2sfi
        MLICALL P_SETINFO, sfip
        bcs @err0
@ok:    lda #0
        clc
        rts
@errc:  pha
        stz closeref
        MLICALL P_CLOSE, closep
        pla
@errd:  pha
        SETPTR despath, fp2
        MLICALL P_DESTROY, desp
        pla
@err0:  jsr showerr
        sec
        rts

gfi2sfi:
        lda gfiacc
        sta sfiacc
        lda gfitype
        sta sfitype
        lda gfiaux
        sta sfiaux
        lda gfiaux+1
        sta sfiaux+1
        lda gfimd
        sta sfimd
        lda gfimd+1
        sta sfimd+1
        lda gfimt
        sta sfimt
        lda gfimt+1
        sta sfimt+1
        rts

;--------------------------------------------------------------------
; Rename / move (6)
;--------------------------------------------------------------------
k_move: jsr selcount
        lda nsel
        bne :+
        jmp main_key
:       jsr otherpath_to_dst
        jsr samedir
        beq @usename
        ldy dstdir
@c1:    lda dstdir,y
        sta inbuf,y
        dey
        bpl @c1
        bra @ask
@usename:
        jsr selinit
        jsr selnext
        ldy selname
@c2:    lda selname,y
        sta inbuf,y
        dey
        bpl @c2
@ask:   lda #<t_renmov
        ldy #>t_renmov
        jsr dlgbox
        GOTO 14,9
        PRINT s_renmov
        lda nsel
        jsr prdec
        PRINT s_itemsto
        jsr input
        bcc :+
        jmp main_redraw
:       lda inbuf
        bne :+
        jmp main_redraw
:       ldy inbuf
@s:     lda inbuf,y
        cmp #'/'
        beq @move
        dey
        bne @s
        ; --- plain rename inside the current directory
        lda nsel
        cmp #1
        beq :+
        lda #ERR_ONE
        jmp @err
:       lda inbuf
        cmp #16
        bcc :+
        lda #$40
        jmp @err
:       jsr selinit
        jsr selnext
        jsr pathptr
        SETPTR ptr2, fp1
        jsr catpath
        ldy inbuf
@c3:    lda inbuf,y
        sta selname,y
        dey
        bpl @c3
        jsr pathptr
        SETPTR ptr2, fp2
        jsr catpath
        bcc :+
        lda #ERR_LONG
        bra @err
:       MLICALL P_RENAME, renp
        bcs @err
        ldy selname
@c5:    lda selname,y
        sta tmpname,y
        dey
        bpl @c5
        jsr reloadboth
        jsr findtmp
        jmp main_redraw
        ; --- move into a directory
@move:  lda inbuf+1
        cmp #'/'
        beq :+
        lda #$40
        bra @err
:       ldy inbuf
        lda inbuf,y
        cmp #'/'
        bne :+
        dec inbuf
:       ldy inbuf
@c4:    lda inbuf,y
        sta dstdir,y
        dey
        bpl @c4
        SETPTR gfipath, dstdir
        MLICALL P_GETINFO, gfip
        bcs @err
        lda gfistyp
        cmp #$0D
        beq :+
        cmp #$0F
        beq :+
        lda #ERR_NOTDIR
        bra @err
:       jsr samedir
        bne :+
        lda #ERR_SAME
        bra @err
:       lda #1
        sta moveflag
        jsr copyloop
        stz moveflag
        jsr reloadboth
        jmp main_redraw
@err:   jsr showerr
        jmp main_redraw

;--------------------------------------------------------------------
; Make directory (7)
;--------------------------------------------------------------------
k_mkdir:
        stz inbuf
        lda #<t_mkdir
        ldy #>t_mkdir
        jsr dlgbox
        GOTO 14,9
        PRINT s_mkdir
        jsr input
        bcs @x
        lda inbuf
        beq @x
        cmp #16
        bcs @bad
        tay
@c:     lda inbuf,y
        sta selname,y
        sta tmpname,y
        dey
        bpl @c
        jsr pathptr
        SETPTR ptr2, fp1
        jsr catpath
        bcs @long
        SETPTR crpath, fp1
        lda #$C3
        sta cracc
        lda #$0F
        sta crtype
        stz craux
        stz craux+1
        lda #$0D
        sta crstyp
        stz crcd
        stz crcd+1
        stz crct
        stz crct+1
        MLICALL P_CREATE, crp
        bcs @err
        jsr reloadboth
        jsr findtmp
@x:     jmp main_redraw
@long:  lda #ERR_LONG
        bra @err
@bad:   lda #$40
@err:   jsr showerr
        jmp main_redraw

;--------------------------------------------------------------------
; Delete (8)
;--------------------------------------------------------------------
k_delete:
        jsr selcount
        lda nsel
        bne :+
        jmp main_key
:       lda #<t_delete
        ldy #>t_delete
        jsr dlgbox
        GOTO 14,9
        PRINT s_delete
        lda nsel
        jsr prdec
        PRINT s_items
        lda nsel
        cmp #1
        bne :+
        jsr selinit
        jsr selnext
        GOTO 14,11
        SETPTR ptr, selname
        lda #15
        jsr pstr
:       GOTO 14,13
        PRINT s_yn
        jsr yesno
        bcs :+
        jmp main_redraw
:       jsr selinit
@l:     jsr selnext
        JCS @done
        jsr pathptr
        SETPTR ptr2, fp1
        jsr catpath
        bcc :+
        lda #ERR_LONG
        jmp @err
:       SETPTR despath, fp1
        jsr destroy
        bcc @l
        cmp #$4E
        bne @err
        lda seltype
        cmp #$0F
        bne @locked
        lda #ERR_NOTEMPTY
        bra @err
@locked:
        lda #<t_delete
        ldy #>t_delete
        jsr dlgbox
        GOTO 14,10
        SETPTR ptr, selname
        lda #15
        jsr pstr
        PRINT s_locked
        GOTO 14,13
        PRINT s_dellock
        jsr yesno
        bcc @l
        SETPTR gfipath, fp1
        MLICALL P_GETINFO, gfip
        bcs @err
        jsr gfi2sfi
        lda #$C3
        sta sfiacc
        SETPTR sfipath, fp1
        MLICALL P_SETINFO, sfip
        bcs @err
        jsr destroy
        bcs @err
        jmp @l
@err:   jsr showerr
@done:  jsr reloadboth
        jmp main_redraw


;--------------------------------------------------------------------
; Lock / unlock (4)
;--------------------------------------------------------------------
k_lock: jsr selcount
        lda nsel
        bne :+
        jmp main_key
:       lda #<t_lock
        ldy #>t_lock
        jsr dlgbox
        GOTO 14,9
        PRINT s_lockq
        lda nsel
        jsr prdec
        PRINT s_items
        lda nsel
        cmp #1
        bne :+
        jsr selinit
        jsr selnext
        GOTO 14,11
        SETPTR ptr, selname
        lda #15
        jsr pstr
:       GOTO 14,13
        PRINT s_lu
@k:     jsr getkey
        cmp #$1B
        bne :+
        jmp main_redraw
:       and #$DF
        cmp #'L'
        beq @lk
        cmp #'B'
        bne :+
        jmp mkboot
:       cmp #'U'
        bne @k
        lda #1
        bra @m
@lk:    lda #0
@m:     sta lockmode
        jsr selinit
@l:     jsr selnext
        bcs @done
        jsr pathptr
        SETPTR ptr2, fp1
        jsr catpath
        bcc :+
        lda #ERR_LONG
        bra @err
:       SETPTR gfipath, fp1
        MLICALL P_GETINFO, gfip
        bcs @err
        jsr gfi2sfi
        lda lockmode
        bne @un
        lda sfiacc
        and #$3D                ; clear destroy, rename, write
        bra @set
@un:    lda sfiacc
        ora #$C3                ; destroy, rename, write, read
@set:   sta sfiacc
        SETPTR sfipath, fp1
        MLICALL P_SETINFO, sfip
        bcs @err
        bra @l
@err:   jsr showerr
@done:  jsr reloadboth
        jmp main_redraw


;--------------------------------------------------------------------
; Make the .SYSTEM file under the cursor the one ProDOS boots:
; swap its volume-directory entry with the first .SYSTEM entry.
;--------------------------------------------------------------------
mkboot: jsr pathdepth
        cmp #1
        bne @nr
        ldx pn
        lda pcount,x
        beq @nr
        lda pcur,x
        jsr lentptr
        ldy #E_TYPE
        lda (ep),y
        cmp #$FF
        bne @nr
        jsr setselname
        jsr issysname
        bcc :+
@nr:    lda #ERR_BOOT
        jmp @err
:       jsr getvolname          ; find the unit of this volume
        jsr findunit
        bcc :+
        jmp @err
:       stz closeref
        MLICALL P_CLOSE, closep
        stz firstblk
        stz firstblk+1
        lda #2
        sta curblk
        stz curblk+1
@rb:    lda curblk
        ldy curblk+1
        ldx #>BUFA
        jsr rdblock
        bcc :+
        jmp @err
:       SETPTR ptr2, BUFA+4
        lda #13
        sta cnt
@en:    lda (ptr2)
        beq @nx
        and #$F0
        cmp #$E0
        bcs @nx
        lda firstblk
        ora firstblk+1
        bne @tg
        jsr entsys
        bcs @tg
        lda curblk
        sta firstblk
        lda curblk+1
        sta firstblk+1
        sec
        lda ptr2
        sbc #<BUFA
        sta firstoff
        lda ptr2+1
        sbc #>BUFA
        sta firstoff+1
@tg:    jsr entissel
        bcc @found
@nx:    clc
        lda ptr2
        adc #39
        sta ptr2
        bcc :+
        inc ptr2+1
:       dec cnt
        bne @en
        lda BUFA+2
        sta curblk
        lda BUFA+3
        sta curblk+1
        ora curblk
        bne @rb
        lda #$46
        jmp @err
@found: sec                     ; tgtoff = ptr2 - BUFA ; tgtblk = curblk
        lda ptr2
        sbc #<BUFA
        sta tgtoff
        lda ptr2+1
        sbc #>BUFA
        sta tgtoff+1
        lda firstblk
        cmp curblk
        bne @swap
        lda firstblk+1
        cmp curblk+1
        bne @swap
        lda firstoff
        cmp tgtoff
        bne @swap
        lda firstoff+1
        cmp tgtoff+1
        bne @swap
        lda #<s_already
        ldy #>s_already
        jmp @msg
@swap:  ; first entry's block -> BUFA, target block -> BUFB (or BUFA)
        lda curblk
        ldy curblk+1
        ldx #>BUFB
        jsr rdblock
        JCS @err
        lda firstblk
        ldy firstblk+1
        ldx #>BUFA
        jsr rdblock
        JCS @err
        lda firstblk
        cmp curblk
        bne @two
        lda firstblk+1
        cmp curblk+1
        bne @two
        lda #>BUFA              ; same block: both entries in BUFA
        bra :+
@two:   lda #>BUFB
:       sta tmp
        clc
        lda tgtoff
        adc #<BUFA
        sta ptr2
        lda tgtoff+1
        adc tmp
        sta ptr2+1
        clc
        lda firstoff
        adc #<BUFA
        sta ptr
        lda firstoff+1
        adc #>BUFA
        sta ptr+1
        ldy #38
@sw:    lda (ptr),y
        tax
        lda (ptr2),y
        sta (ptr),y
        txa
        sta (ptr2),y
        dey
        bpl @sw
        lda tmp
        cmp #>BUFB
        bne @one
        lda curblk
        ldy curblk+1
        ldx #>BUFB
        jsr wrblock
        bcs @err
@one:   lda firstblk
        ldy firstblk+1
        ldx #>BUFA
        jsr wrblock
        bcs @err
        lda #<s_bootok
        ldy #>s_bootok
@msg:   pha
        phy
        lda #<t_boot
        ldy #>t_boot
        jsr dlgbox
        GOTO 14,10
        SETPTR ptr, selname
        lda #15
        jsr pstr
        ply
        pla
        jsr puts
        GOTO 14,13
        PRINT s_anykey
        jsr getkey
        jsr reloadboth
        jmp main_redraw
@err:   jsr showerr
        jsr reloadboth
        jmp main_redraw

; read/write block A=lo Y=hi into page X ; C=1 error
rdblock:
        sta blkno
        sty blkno+1
        stx blkbuf+1
        stz blkbuf
        MLICALL P_RDBLK, blkp
        rts
wrblock:
        sta blkno
        sty blkno+1
        stx blkbuf+1
        stz blkbuf
        MLICALL P_WRBLK, blkp
        rts

; C=0 if selname ends in ".SYSTEM"
issysname:
        lda selname
        cmp #8
        bcc @no
        sbc #7
        tay
        ldx #0
@l:     iny
        lda selname,y
        cmp s_dotsys,x
        bne @no
        inx
        cpx #7
        bne @l
        clc
        rts
@no:    sec
        rts

; C=0 if directory entry (ptr2) is a SYS file named *.SYSTEM
entsys: ldy #$10
        lda (ptr2),y
        cmp #$FF
        bne @no
        lda (ptr2)
        and #$0F
        cmp #8
        bcc @no
        sbc #7
        tay
        ldx #0
@l:     iny
        lda (ptr2),y
        cmp s_dotsys,x
        bne @no
        inx
        cpx #7
        bne @l
        clc
        rts
@no:    sec
        rts

; C=0 if directory entry (ptr2) has the name in selname
entissel:
        lda (ptr2)
        and #$0F
        cmp selname
        bne @no
        tay
@l:     lda (ptr2),y
        cmp selname,y
        bne @no
        dey
        bne @l
        clc
        rts
@no:    sec
        rts

;--------------------------------------------------------------------
; Extended files (storage type 5: data fork + resource fork, made by
; GS/OS).  ProDOS 8 can't open or destroy them, so YANC works on them
; at block level.  All block allocation is still done by ProDOS:
; each fork is written to / freed through a temporary file
; (YANCTMP.0 / YANCTMP.1 in the same directory) whose directory entry
; is then edited.
;--------------------------------------------------------------------
IDXBUF      = $B400
MIDXBUF     = $B600
KEYBUF      = $B800

; DESTROY the file at despath, extended files too.  C=1 A=error
destroy:
        MLICALL P_DESTROY, desp
        bcc @r
        cmp #$4A                ; ProDOS 8 2.x: incompatible file format
        beq delext
        cmp #$4B                ; unsupported storage type
        beq delext
        sec
@r:     rts

; delete an extended file: free each fork through a temporary file,
; then turn the file into a sapling whose index block (the old
; extended key block) lists the two temporary key blocks, and DESTROY it
delext: lda despath
        sta xpath
        lda despath+1
        sta xpath+1
        jsr xfind
        bcs @r
        ldy #$1E
        lda (ptr2),y
        bmi :+
        lda #$4E                ; locked
        sec
@r:     rts
:       jsr rdkey
        bcs @r
        lda xpath
        ldy xpath+1
        jsr mktmp
        bcs @r
        stz fork
@fk:    jsr forkptr
        ldx fork
        stz tkeyl,x
        stz tkeyh,x
        lda (vp)
        beq @nf
        jsr tcreate
        bcs @r
        jsr tfind
        bcs @r
        ldx fork
        ldy #$11
        lda (ptr2),y
        sta tkeyl,x
        iny
        lda (ptr2),y
        sta tkeyh,x
        lda (vp)                ; temp entry -> this fork
        asl a
        asl a
        asl a
        asl a
        sta tmp
        lda (ptr2)
        and #$0F
        ora tmp
        sta (ptr2)
        jsr ent16
        ldy #7
:       lda (vp),y
        sta (ep2),y
        dey
        bne :-
        jsr wrcur
        bcs @r
        jsr tsetd
        MLICALL P_DESTROY, tdesp
        bcs @r
@nf:    inc fork
        lda fork
        cmp #2
        bne @fk
        lda #>KEYBUF
        jsr zero2
        ldx #1
:       lda tkeyl,x
        sta KEYBUF,x
        lda tkeyh,x
        sta KEYBUF+256,x
        dex
        bpl :-
        lda extkey
        ldy extkey+1
        ldx #>KEYBUF
        jsr wrblock
        bcs @r2
        jsr xfind
        bcs @r2
        lda (ptr2)
        and #$0F
        ora #$20                ; sapling
        sta (ptr2)
        ldy #$15                ; EOF = $000400
        lda #0
        sta (ptr2),y
        iny
        lda #4
        sta (ptr2),y
        iny
        lda #0
        sta (ptr2),y
        jsr wrcur
        bcs @r2
        MLICALL P_DESTROY, desp
@r2:    rts

; copy the extended file fp1 to fp2 (just created as an empty file)
; C=1 A=error
cpext:  stz tmade
        stz tmade+1
        lda #<fp1
        ldy #>fp1
        jsr findent
        JCS @r
        jsr rdkey
        JCS @r
        lda blkunit
        sta srcunit
        lda #<fp2
        ldy #>fp2
        jsr mktmp
        JCS @r
        SETPTR sfipath, fp2     ; type, dates, access - while it's a plain file
        jsr gfi2sfi
        MLICALL P_SETINFO, sfip
        JCS @r
        ; 1: write each fork to a temporary file
        stz fork
@fk:    jsr forkptr
        lda (vp)
        beq @nf
        jsr tcreate
        JCS @e
        ldx fork
        inc tmade,x
        SETPTR openpath, inbuf
        SETPTR openbuf, IOBUF1
        MLICALL P_OPEN, openp
        JCS @e
        lda openref
        sta writeref
        jsr cpfork
        php
        pha
        stz closeref
        MLICALL P_CLOSE, closep
        pla
        plp
        JCS @e
@nf:    inc fork
        lda fork
        cmp #2
        bne @fk
        ; 2: take the forks over from the temporary files
        stz fork
@mv:    jsr forkptr
        lda (vp)
        beq @mn
        jsr tfind
        JCS @e
        lda (ptr2)
        lsr a
        lsr a
        lsr a
        lsr a
        sta (vp)
        jsr ent16
        ldy #7
:       lda (ep2),y
        sta (vp),y
        dey
        bne :-
        lda #0                  ; remove the temporary entry
        sta (ptr2)
        jsr wrcur
        JCS @e
        ldx fork
        stz tmade,x
        lda dirkey              ; file_count - 1
        ldy dirkey+1
        ldx #>BUFA
        jsr rdblock
        JCS @e
        lda BUFA+$25
        bne :+
        dec BUFA+$26
:       dec BUFA+$25
        lda dirkey
        ldy dirkey+1
        ldx #>BUFA
        jsr wrblock
        JCS @e
@mn:    inc fork
        lda fork
        cmp #2
        bne @mv
        ; 3: make fp2 an extended file, its key block the new extended key block
        lda #<fp2
        ldy #>fp2
        jsr findent
        JCS @e
        lda (ptr2)
        and #$0F
        ora #$50
        sta (ptr2)
        jsr ent16
        ldy #3                  ; blocks used = 1 + both forks
        sec
        lda KEYBUF+3
        adc KEYBUF+$103
        sta (ep2),y
        iny
        lda KEYBUF+4
        adc KEYBUF+$104
        sta (ep2),y
        iny                     ; EOF = $000200
        lda #0
        sta (ep2),y
        iny
        lda #2
        sta (ep2),y
        iny
        lda #0
        sta (ep2),y
        jsr wrcur
        JCS @e
        ldy #2
        lda (ep2),y
        tax
        dey
        lda (ep2),y
        phx
        ply
        ldx #>KEYBUF
        jmp wrblock
@e:     pha                     ; error: remove the temporary files
        stz closeref
        MLICALL P_CLOSE, closep
        stz fork
@d:     ldx fork
        lda tmade,x
        beq :+
        jsr tsetd
        MLICALL P_DESTROY, tdesp
:       inc fork
        lda fork
        cmp #2
        bne @d
        pla
        sec
@r:     rts

; write the fork at (vp) of the source file (unit srcunit) to file writeref
cpfork: lda srcunit
        sta blkunit
        ldy #7
:       lda (vp),y
        sta fhdr,y
        dey
        bpl :-
        stz bidx
        stz bidx+1
        lda fhdr
        cmp #2
        bcc @seed
        ldx #>IDXBUF
        cmp #3
        bne :+
        ldx #>MIDXBUF
:       lda fhdr+1
        ldy fhdr+2
        jsr rdblock
        bcc @loop
        rts
@seed:  lda #>IDXBUF            ; seedling: fake index block
        jsr zero2
        lda fhdr+1
        sta IDXBUF
        lda fhdr+2
        sta IDXBUF+256
@loop:  lda fhdr+5              ; bytes left
        ora fhdr+6
        ora fhdr+7
        bne :+
        clc
        rts
:       lda fhdr
        cmp #3
        bne @dat
        lda bidx
        bne @dat
        ldx bidx+1              ; tree: next index block
        lda MIDXBUF,x
        ldy MIDXBUF+256,x
        ldx #>IDXBUF
        jsr rdblkz
        bcs @r
@dat:   ldx bidx
        lda IDXBUF,x
        ldy IDXBUF+256,x
        ldx #>COPYBUF
        jsr rdblkz
        bcs @r
        lda fhdr+7
        bne @full
        lda fhdr+6
        cmp #2
        bcs @full
        lda fhdr+5
        sta writereq
        lda fhdr+6
        sta writereq+1
        bra @w
@full:  stz writereq
        lda #2
        sta writereq+1
@w:     MLICALL P_WRITE, writep
        bcs @r
        sec
        lda fhdr+5
        sbc writereq
        sta fhdr+5
        lda fhdr+6
        sbc writereq+1
        sta fhdr+6
        lda fhdr+7
        sbc #0
        sta fhdr+7
        inc bidx
        bne :+
        inc bidx+1
:
        jmp @loop
@r:     rts

; read block A/Y into page X, or clear the page when the block is 0 (sparse)
rdblkz: sta tmp
        tya
        ora tmp
        bne :+
        txa
        jsr zero2
        clc
        rts
:       lda tmp
        jmp rdblock

; clear the two pages starting at page A
zero2:  sta sptr+1
        stz sptr
        lda #0
        tay
        ldx #2
:       sta (sptr),y
        iny
        bne :-
        inc sptr+1
        dex
        bne :-
        rts

; vp -> mini entry of fork 'fork' in KEYBUF
forkptr:
        stz vp
        lda fork
        clc
        adc #>KEYBUF
        sta vp+1
        rts

; ep2 = ptr2 + $10 (so (ep2),1..7 = key, blocks used, EOF)
ent16:  clc
        lda ptr2
        adc #$10
        sta ep2
        lda ptr2+1
        adc #0
        sta ep2+1
        rts

; key block of entry (ptr2) -> extkey, read it into KEYBUF
rdkey:  ldy #$11
        lda (ptr2),y
        sta extkey
        iny
        lda (ptr2),y
        sta extkey+1
        tay
        lda extkey
        ldx #>KEYBUF
        jmp rdblock

wrcur:  lda curblk
        ldy curblk+1
        ldx #>BUFA
        jmp wrblock

xfind:  lda xpath
        ldy xpath+1
        jmp findent

; temporary file name: last character = fork number
tsetd:  lda fork
        ora #'0'
        ldy inbuf
        sta inbuf,y
        rts
tcreate:
        jsr tsetd
        MLICALL P_CREATE, crtp
        rts
tfind:  jsr tsetd
        lda #<inbuf
        ldy #>inbuf
        jmp findent

; inbuf = directory of the path at A/Y + "/YANCTMP.0" ; C=1 too long
mktmp:  sta ptr
        sty ptr+1
        lda (ptr)
        tay
:       lda (ptr),y
        cmp #'/'
        beq :+
        dey
        bne :-
:       cpy #56
        bcs @long
        sty tmp
:       lda (ptr),y
        sta inbuf,y
        dey
        bne :-
        ldy tmp
        ldx #0
:       lda s_tmpn,x
        iny
        sta inbuf,y
        inx
        cpx #9
        bne :-
        sty inbuf
        clc
        rts
@long:  lda #ERR_LONG
        rts

; find the directory entry of the file with full path A/Y by reading
; directory blocks.  C=0: ptr2 -> entry in BUFA, curblk = that block,
; dirkey = key block of its directory, blkunit = its unit
findent:
        sta ptr
        sty ptr+1
        jsr getvn2
        jsr findunit
        JCS @r
        lda (ptr)
        inc a
        sta plen1
        lda #2
        sta curblk
        stz curblk+1
        ldy vbuf                ; last character of the volume name
        iny                     ; the '/' after it
@comp:  iny                     ; skip '/', next name -> tmpname
        ldx #0
@cc:    cpy plen1
        bcs @ce
        lda (ptr),y
        cmp #'/'
        beq @ce
        inx
        sta tmpname,x
        iny
        bra @cc
@ce:    stx tmpname
        sty pidx
        lda curblk
        sta dirkey
        lda curblk+1
        sta dirkey+1
@rb:    lda curblk
        ldy curblk+1
        ldx #>BUFA
        jsr rdblock
        bcs @r
        SETPTR ptr2, BUFA+4
        lda #13
        sta cnt
@en:    lda (ptr2)
        beq @nx
        and #$F0
        cmp #$E0
        bcs @nx
        jsr entisnm
        bcc @fnd
@nx:    clc
        lda ptr2
        adc #39
        sta ptr2
        bcc :+
        inc ptr2+1
:       dec cnt
        bne @en
        lda BUFA+2
        sta curblk
        lda BUFA+3
        sta curblk+1
        ora curblk
        bne @rb
        lda #$46
        sec
@r:     rts
@fnd:   ldy pidx
        cpy plen1
        bcc :+
        clc                     ; last name of the path
        rts
:       ldy #$11                ; a directory: go into it
        lda (ptr2),y
        sta curblk
        iny
        lda (ptr2),y
        sta curblk+1
        ldy pidx
        jmp @comp

; C=0 if directory entry (ptr2) has the name in tmpname
entisnm:
        lda (ptr2)
        and #$0F
        cmp tmpname
        bne @no
        tay
@l:     lda (ptr2),y
        cmp tmpname,y
        bne @no
        dey
        bne @l
        clc
        rts
@no:    sec
        rts

; unit of volume vbuf -> blkunit ; C=1 A=$45 if not on line
findunit:
        jsr scanvols
        ldx #0
@uv:    cpx vn
        bne :+
        lda #$45
        sec
        rts
:       ldy vl,x
        jsr cmpvol
        beq @uf
        inx
        bra @uv
@uf:    ldy vl,x
        lda onbuf,y
        and #$F0
        sta blkunit
        clc
        rts

s_tmpn: .byte "YANCTMP.0"

;--------------------------------------------------------------------
; Viewer (3)
;--------------------------------------------------------------------
k_view: ldx pn
        lda pcount,x
        bne :+
@no:    jmp main_key
:       lda pcur,x
        jsr lentptr
        ldy #E_STOR
        lda (ep),y
        cmp #$FF
        beq @no
        ldy #E_TYPE
        lda (ep),y
        cmp #$0F
        beq @no
        jsr setselname
        jsr pathptr
        SETPTR ptr2, fp1
        jsr catpath
        bcc :+
        lda #ERR_LONG
        jsr showerr
        jmp main_redraw
:       SETPTR openpath, fp1
        SETPTR openbuf, IOBUF1
        MLICALL P_OPEN, openp
        bcc :+
        jsr showerr
        jmp main_redraw
:       lda openref
        sta readref
        sta markref
        stz hexmode
        stz vpage
        stz mk0
        stz mk1
        stz mk2
vw_page:
        ldx vpage
        lda mk0,x
        sta markpos
        lda mk1,x
        sta markpos+1
        lda mk2,x
        sta markpos+2
        MLICALL P_SETMARK, markp
        SETPTR readbuf, COPYBUF
        SETPTR readreq, VIEWLEN
        MLICALL P_READ, readp
        bcc :+
        stz readtrn
        stz readtrn+1
:       clc
        lda #<COPYBUF
        adc readtrn
        sta vendp
        lda #>COPYBUF
        adc readtrn+1
        sta vendp+1
        SETPTR vp, COPYBUF
        jsr cls
        GOTO 0,0
        lda #$80
        sta attr
        PRINT s_view
        SETPTR ptr, fp1
        lda #56
        jsr pstr
        lda hexmode
        beq :+
        PRINT s_hex
        bra :++
:       PRINT s_text
:       jsr fillinv
        GOTO 0,23
        lda #$80
        sta attr
        PRINT s_vkeys
        jsr fillinv
        stz attr
        lda hexmode
        beq :+
        jsr vw_hex
        bra vw_key
:       jsr vw_text
vw_key: jsr getkey
        cmp #$1B
        beq vw_exit
        cmp #'3'
        beq vw_exit
        cmp #' '
        beq vw_next
        cmp #$0A
        beq vw_next
        cmp #$15
        beq vw_next
        cmp #$0B
        beq vw_prev
        cmp #$08
        beq vw_prev
        and #$DF
        cmp #'Q'
        beq vw_exit
        cmp #'H'
        bne vw_key
        ldx vpage
        lda mk0,x
        sta mk0
        lda mk1,x
        sta mk1
        lda mk2,x
        sta mk2
        stz vpage
        lda hexmode
        eor #1
        sta hexmode
        jmp vw_page
vw_next:
        lda vendf
        bne vw_key
        ldx vpage
        cpx #255
        beq vw_key
        inx
        stx vpage
        lda vnext
        sta mk0,x
        lda vnext+1
        sta mk1,x
        lda vnext+2
        sta mk2,x
        jmp vw_page
vw_prev:
        lda vpage
        beq vw_key
        dec vpage
        jmp vw_page
vw_exit:
        stz closeref
        MLICALL P_CLOSE, closep
        jsr cls
        jmp main_redraw

; fill current row to column 80 with spaces (current attr)
fillinv:
@l:     lda cx
        cmp #80
        bcs @d
        lda #' '
        jsr putc
        bra @l
@d:     stz attr
        rts

vw_text:
        lda #1
        sta row
        stz lastcr
        GOTO 0,1
@c:     jsr vatend
        bcs @fin
        lda (vp)
        and #$7F
        inc vp
        bne :+
        inc vp+1
:       cmp #$0D
        beq @cr
        cmp #$0A
        beq @lf
        stz lastcr
        cmp #$09
        beq @tab
        cmp #$20
        bcc @ctl
        cmp #$7F
        bne @pc
@ctl:   lda #'.'
@pc:    jsr putc
        lda cx
        cmp #80
        bcc @c
        jsr vnl
        bcs @fin
        bra @c
@tab:   lda #' '
        jsr putc
        lda cx
        cmp #80
        bcs @tw
        and #7
        bne @tab
        bra @c
@tw:    jsr vnl
        bcs @fin
        bra @c
@lf:    lda lastcr
        stz lastcr
        bne @c
        bra @nl
@cr:    lda #1
        sta lastcr
@nl:    jsr vnl
        bcs @fin
        bra @c
@fin:   jmp vw_fin

; next viewer line; C=1 if page full
vnl:    inc row
        lda row
        cmp #23
        bcs @r
        ldx #0
        ldy row
        jsr gotoxy
        clc
@r:     rts

; C=1 if vp >= vendp
vatend: lda vp+1
        cmp vendp+1
        bne @r
        lda vp
        cmp vendp
@r:     rts

; compute vendf and vnext = mark + (vp - COPYBUF)
vw_fin: stz vendf
        jsr vatend
        bcc :+
        inc vendf
:       sec
        lda vp
        sbc #<COPYBUF
        sta tmp
        lda vp+1
        sbc #>COPYBUF
        sta tmp2
        ldx vpage
        clc
        lda mk0,x
        adc tmp
        sta vnext
        lda mk1,x
        adc tmp2
        sta vnext+1
        lda mk2,x
        adc #0
        sta vnext+2
        rts

vw_hex: lda #1
        sta row
        ldx vpage
        lda mk0,x
        sta vaddr
        lda mk1,x
        sta vaddr+1
        lda mk2,x
        sta vaddr+2
@r:     jsr vatend
        JCS @done
        ldx #0
        ldy row
        jsr gotoxy
        lda vaddr+2
        jsr prhex
        lda vaddr+1
        jsr prhex
        lda vaddr
        jsr prhex
        lda #':'
        jsr putc
        lda #' '
        jsr putc
        ldy #0
@b:     jsr vhave
        bcs @bl
        lda (vp),y
        jsr prhex
        lda #' '
        jsr putc
        bra @bn
@bl:    lda #' '
        jsr putc
        jsr putc
        jsr putc
@bn:    iny
        cpy #16
        bne @b
        lda #' '
        jsr putc
        ldy #0
@a:     jsr vhave
        bcs @an
        lda (vp),y
        and #$7F
        cmp #$20
        bcc @dot
        cmp #$7F
        bne @p
@dot:   lda #'.'
@p:     jsr putc
@an:    iny
        cpy #16
        bne @a
        clc
        lda vp
        adc #16
        sta vp
        bcc :+
        inc vp+1
:       clc
        lda vaddr
        adc #16
        sta vaddr
        bcc :+
        inc vaddr+1
        bne :+
        inc vaddr+2
:       inc row
        lda row
        cmp #23
        JCC @r
@done:  jmp vw_fin

; C=1 if vp+Y >= vendp   (preserves Y)
vhave:  tya
        clc
        adc vp
        sta tmp
        lda vp+1
        adc #0
        cmp vendp+1
        bne @r
        lda tmp
        cmp vendp
@r:     rts


;--------------------------------------------------------------------
; Return on a file: SYS runs directly, BAS/BIN via BASIC.SYSTEM,
; TXT opens the viewer.
;--------------------------------------------------------------------
runfile:
        ldy #E_TYPE
        lda (ep),y
        cmp #$04
        bne :+
        jmp k_view
:       cmp #$FF
        beq @sys
        cmp #$FC
        beq @bas
        cmp #$06
        beq @bas
        jmp main_key
@sys:   stz lmode
        jsr setselname
        jsr pathptr
        SETPTR ptr2, fp2                ; fp2 = file to load
        jsr catpath
        bcs @long
        jmp launch
@bas:   lda #1
        sta lmode
        jsr setselname
        jsr pathptr
        SETPTR ptr2, fp1                ; fp1 = program to start
        jsr catpath
        bcs @long
        ldy #12                         ; look for BASIC.SYSTEM
:       lda s_bs,y
        sta selname,y
        dey
        bpl :-
        jsr pathptr                     ; 1) same directory
        jsr trybs
        bcc @found
        jsr getvolname                  ; 2) volume root
        SETPTR ptr, vbuf
        jsr trybs
        bcc @found
        SETPTR ptr, startdir            ; 3) directory NC started from
        jsr trybs
        bcc @found
        lda #ERR_NOBS
        bra @err
@found: jmp launch
@long:  lda #ERR_LONG
@err:   jsr showerr
        jmp main_redraw

; fp2 = (ptr) + "/" + selname ; C=0 if it exists and is a SYS file
trybs:  SETPTR ptr2, fp2
        jsr catpath
        bcs @no
        SETPTR gfipath, fp2
        MLICALL P_GETINFO, gfip
        bcs @no
        lda gfitype
        cmp #$FF
        bne @no
        clc
        rts
@no:    sec
        rts

; load fp2 at $2000 and run it (lmode=1: pass fp1 as startup path)
launch: jsr pathptr                     ; prefix = directory of the file
        lda ptr
        sta pfxsp
        lda ptr+1
        sta pfxsp+1
        MLICALL P_SETPFX, pfxsetp
        stz closeref
        MLICALL P_CLOSE, closep
        ldx #0                          ; copy loader to $1000
:       lda __LOADER_LOAD__,x
        sta LOADER,x
        lda __LOADER_LOAD__+$100,x
        sta LOADER+$100,x
        lda __LOADER_LOAD__+$200,x
        sta LOADER+$200,x
        inx
        bne :-
        ldx #64
:       lda fp2,x
        sta ldpath,x
        lda fp1,x
        sta ldspath,x
        dex
        bpl :-
        lda lmode
        sta ldmode
        ; back to a normal 40-column text screen
        lda $37                         ; output hooked to 80-col firmware?
        cmp #$C3
        bne :+
        lda #$95                        ; Ctrl-U: turn 80-col firmware off
        jsr $FDED
:       sta $C00C                       ; 80COL off
        sta $C000                       ; 80STORE off
        sta $C00E                       ; ALTCHAR off
        sta TXTPAGE1
        jsr $FE84                       ; SETNORM
        jsr $FB2F                       ; INIT
        jsr $FE93                       ; SETVID
        jsr $FE89                       ; SETKBD
        jsr $FC58                       ; HOME
        jmp ldstart

;--------------------------------------------------------------------
; Loader: copied to $1000, loads a SYS file at $2000 and jumps to it
;--------------------------------------------------------------------
        .segment "LOADER"
ldstart:
        ldx #$FF
        txs
        ldx #$17                        ; fresh memory bitmap
        lda #0
:       sta $BF58,x
        dex
        bpl :-
        lda #$CF
        sta $BF58
        lda #$01
        sta $BF6F
        MLICALL P_OPEN, ldopen
        bcs ldfail
        lda ldref
        sta ldrref
        sta ldcref
        MLICALL P_READ, ldread
        bcs ldfail
        MLICALL P_CLOSE, ldclose
        lda ldmode
        beq @go
        lda $2000                       ; startup-path convention
        cmp #$4C
        bne @go
        lda $2003
        cmp #$EE
        bne @go
        lda $2004
        cmp #$EE
        bne @go
        lda ldspath
        cmp $2005
        bcs @go
        tax
:       lda ldspath,x
        sta $2006,x
        dex
        bpl :-
@go:    ldx #64                         ; ProDOS convention: pathname of
:       lda ldpath,x                    ; the running system program at $280
        sta $0280,x
        dex
        bpl :-
        jmp $2000
ldfail: MLICALL P_QUIT, ldquit
        brk
ldopen: .byte 3
        .word ldpath
        .word LDIOBUF
ldref:  .byte 0
ldread: .byte 4
ldrref: .byte 0
        .word $2000
        .word $BF00-$2000
        .word 0
ldclose:.byte 1
ldcref: .byte 0
ldquit: .byte 4, 0, 0, 0, 0, 0, 0
ldmode: .byte 0
ldpath: .res 65
ldspath:.res 65
        .code

;====================================================================
; Selection helpers
;====================================================================
selcount:
        stz nsel
        jsr selinit
@l:     jsr selnext
        bcs @d
        inc nsel
        bra @l
@d:     rts

selinit:
        lda #$FF
        sta sel_l
        rts

; next selected entry -> selname, seltype ; C=1 when done
selnext:
@l:     inc sel_l
        ldx pn
        lda sel_l
        cmp pcount,x
        bcs @done
        lda pntag,x
        beq @cur
        lda sel_l
        jsr lentptr
        ldy #E_TAG
        lda (ep),y
        beq @l
        bra @got
@cur:   lda sel_l
        cmp pcur,x
        bne @l
        jsr lentptr
        ldy #E_STOR
        lda (ep),y
        cmp #$FF
        beq @done
@got:   jsr setselname
        ldy #E_TYPE
        lda (ep),y
        sta seltype
        clc
        rts
@done:  sec
        rts

setselname:
        lda (ep)
        tay
@c:     lda (ep),y
        sta selname,y
        dey
        bpl @c
        rts

; (ptr)=dir path, (ptr2)=dest ; dest = dir + "/" + selname ; C=1 too long
catpath:
        lda (ptr)
        sta tmp
        sec
        adc selname
        cmp #65
        bcs @long
        ldy tmp
@c:     lda (ptr),y
        sta (ptr2),y
        dey
        bne @c
        ldy tmp
        iny
        lda #'/'
        sta (ptr2),y
        ldx #0
@n:     cpx selname
        beq @e
        iny
        lda selname+1,x
        sta (ptr2),y
        inx
        bra @n
@e:     tya
        sta (ptr2)
        clc
        rts
@long:  sec
        rts

;====================================================================
; Panels / directories
;====================================================================
pathptr:
        ldx pn
        lda ppl,x
        sta ptr
        lda pph,x
        sta ptr+1
        rts
ppl:    .byte <path0, <path1
pph:    .byte >path0, >path1
entbase:.byte ENTA_HI, ENTB_HI

setpx:  lda pn
        beq :+
        lda #40
:       sta px
        rts

; A = physical index -> ep
entptr: pha
        asl a
        asl a
        asl a
        asl a
        asl a
        sta ep
        pla
        lsr a
        lsr a
        lsr a
        ldx pn
        clc
        adc entbase,x
        sta ep+1
        rts

; A = logical (sorted) index -> ep
lentptr:
        ldx pn
        beq :+
        ora #$80
:       tax
        lda idxtab,x
        jmp entptr

; number of '/' in path -> A
pathdepth:
        jsr pathptr
        lda (ptr)
        tay
        ldx #0
@l:     lda (ptr),y
        cmp #'/'
        bne :+
        inx
:       dey
        bne @l
        txa
        rts

; "/VOL" part of path(pn) -> vbuf
getvolname:
        jsr pathptr
getvn2:
        lda (ptr)
        sta tmp
        lda #'/'
        sta vbuf+1
        ldy #1
@l:     iny
        cpy tmp
        beq @c
        bcs @e
@c:     lda (ptr),y
        cmp #'/'
        beq @e
        sta vbuf,y
        bra @l
@e:     dey
        sty vbuf
        rts

; compare ON_LINE entry at onbuf+Y with vbuf ; Z=1 equal (X kept)
cmpvol: phx
        lda onbuf,y
        and #$0F
        sta tmp
        inc a
        cmp vbuf
        bne @ne
        ldx #0
@l:     lda onbuf+1,y
        cmp vbuf+2,x
        bne @ne
        iny
        inx
        cpx tmp
        bne @l
        plx
        lda #0
        rts
@ne:    plx
        lda #1
        rts

; path(pn) = "/" + volume name of ON_LINE entry at onbuf+Y
setvol: jsr pathptr
        lda onbuf,y
        and #$0F
        sta tmp
        inc a
        sta (ptr)
        lda #'/'
        phy
        ldy #1
        sta (ptr),y
        ply
        ldx #0
@l:     lda onbuf+1,y
        phy
        pha
        txa
        clc
        adc #2
        tay
        pla
        sta (ptr),y
        ply
        iny
        inx
        cpx tmp
        bne @l
        rts

; ON_LINE -> vl[] (offsets of valid entries), vn
scanvols:
        stz vn
        MLICALL P_ONLINE, onlinep
        ldy #0
@l:     lda onbuf,y
        beq @d
        and #$0F
        beq @n
        ldx vn
        tya
        sta vl,x
        inc vn
@n:     tya
        clc
        adc #16
        tay
        bne @l
@d:     rts

; free / total blocks for panel pn
volinfo:
        jsr getvolname
        SETPTR gfipath, vbuf
        MLICALL P_GETINFO, gfip
        ldx pn
        bcs @err
        sec
        lda gfiaux
        sbc gfiblk
        sta pfreel,x
        lda gfiaux+1
        sbc gfiblk+1
        sta pfreeh,x
        lda gfiaux
        sta ptotl,x
        lda gfiaux+1
        sta ptoth,x
        rts
@err:   stz pfreel,x
        stz pfreeh,x
        stz ptotl,x
        stz ptoth,x
        rts

; reload panel pn keeping cursor position
reloadkeep:
        ldx pn
        lda pcur,x
        pha
        lda ptop,x
        pha
        jsr loaddir
        ldx pn
        pla
        sta ptop,x
        pla
        sta pcur,x
        lda pcount,x
        bne :+
        stz pcur,x
        stz ptop,x
        rts
:       lda pcur,x
        cmp pcount,x
        bcc :+
        lda pcount,x
        dec a
        sta pcur,x
:       lda ptop,x
        cmp pcur,x
        bcc :+
        lda pcur,x
        sta ptop,x
:       jmp fixtop

reloadboth:
        stz pn
        jsr reloadkeep
        lda #1
        sta pn
        jsr reloadkeep
        lda cp
        sta pn
        rts

; keep cursor visible
fixtop: ldx pn
        lda pcur,x
        cmp ptop,x
        bcs @a
        sta ptop,x
        rts
@a:     sec
        sbc ptop,x
        cmp #NROWS
        bcc @ok
        lda pcur,x
        sec
        sbc #NROWS-1
        sta ptop,x
@ok:    rts

; read directory of panel pn
loaddir:
        jsr iskegs
        beq :+
        jmp kloaddir
:       ldx pn
        stz pcount,x
        stz ptop,x
        stz pcur,x
        stz pntag,x
        jsr volinfo
        jsr pathdepth
        cmp #2
        bcc @noup
        lda #0
        jsr entptr
        ldy #31
        lda #0
:       sta (ep),y
        dey
        bpl :-
        lda #2
        sta (ep)
        lda #'.'
        ldy #1
        sta (ep),y
        iny
        sta (ep),y
        lda #$0F
        ldy #E_TYPE
        sta (ep),y
        lda #$FF
        iny
        sta (ep),y
        ldx pn
        inc pcount,x
@noup:  jsr pathptr
        lda ptr
        sta openpath
        lda ptr+1
        sta openpath+1
        SETPTR openbuf, IOBUF1
        MLICALL P_OPEN, openp
        bcc :+
        jmp @err
:       lda openref
        sta readref
        sta closeref
@rdblk: SETPTR readbuf, DIRBLK
        SETPTR readreq, 512
        MLICALL P_READ, readp
        bcs @eof
        SETPTR ptr2, DIRBLK+4
        lda #13
        sta cnt
@ent:   lda (ptr2)
        beq @next
        and #$F0
        cmp #$E0
        bcs @next
        ldx pn
        lda pcount,x
        cmp #MAXENT
        bcs @next
        jsr entptr
        jsr copyent
        ldx pn
        inc pcount,x
@next:  clc
        lda ptr2
        adc #39
        sta ptr2
        bcc :+
        inc ptr2+1
:       dec cnt
        bne @ent
        bra @rdblk
@eof:   pha
        MLICALL P_CLOSE, closep
        pla
        cmp #$4C
        bne @err
        jmp sortpanel
@err:   jsr showerr
        jmp sortpanel

srcoff: .byte $13,$14,$15,$16,$17,$1F,$20,$21,$22,$23,$24,$1E
dstoff: .byte 18,19,20,21,22,23,24,25,26,27,28,29

; directory entry (ptr2) -> panel entry (ep)
copyent:
        lda (ptr2)
        and #$0F
        sta (ep)
        ldy #1
@n:     lda (ptr2),y
        sta (ep),y
        iny
        cpy #17                 ; name (1..15) + file type (16)
        bne @n
        ldx #11
@c:     ldy srcoff,x
        lda (ptr2),y
        ldy dstoff,x
        sta (ep),y
        dex
        bpl @c
        lda (ptr2)
        and #$F0
        ldy #E_STOR
        sta (ep),y
        lda #0
        ldy #E_TAG
        sta (ep),y
        rts

; build index table of panel pn and insertion-sort it
sortpanel:
        ldx pn
        lda pcount,x
        sta sn
        lda pn
        beq :+
        lda #$80
:       sta ib
        ldy #0
@id:    cpy sn
        beq @sort
        tya
        ora ib
        tax
        tya
        sta idxtab,x
        iny
        bra @id
@sort:  ldx pn
        lda pmode,x             ; KEGS panels come sorted
        bne @done
        lda sn
        cmp #2
        bcc @done
        lda #1
        sta si
@outer: lda si
        ora ib
        tax
        lda idxtab,x
        sta skey
        lda si
        sta sj
@inner: lda sj
        beq @place
        ora ib
        tax
        lda idxtab-1,x
        ldx skey
        jsr greater
        bcc @place
        lda sj
        ora ib
        tax
        lda idxtab-1,x
        sta idxtab,x
        dec sj
        bra @inner
@place: lda sj
        ora ib
        tax
        lda skey
        sta idxtab,x
        inc si
        lda si
        cmp sn
        bne @outer
@done:  rts

; C=1 if entry A (physical) sorts after entry X
greater:
        phx
        jsr entptr
        lda ep
        sta ep2
        lda ep+1
        sta ep2+1
        pla
        jsr entptr
        ldy #E_STOR
        lda (ep2),y
        cmp #$FF
        beq @lt
        lda (ep),y
        cmp #$FF
        beq @gt
        ldy #E_TYPE
        lda (ep2),y
        cmp #$0F
        bne @afile
        lda (ep),y
        cmp #$0F
        bne @lt
        bra @same
@afile: lda (ep),y
        cmp #$0F
        beq @gt
@same:  lda sortmode
        beq @name
        ldy #E_TYPE
        lda (ep2),y
        cmp (ep),y
        bne @r
@name:  lda (ep2)
        sta tmp
        lda (ep)
        sta tmp2
        ldy #1
@nl:    lda tmp
        beq @lt
        lda tmp2
        beq @gt
        lda (ep2),y
        cmp (ep),y
        bne @r
        iny
        dec tmp
        dec tmp2
        bra @nl
@lt:    clc
        rts
@gt:    sec
@r:     rts

;====================================================================
; Drawing
;====================================================================
drawall:
        lda pn
        pha
        stz pn
        jsr drawpanel
        lda #1
        sta pn
        jsr drawpanel
        pla
        sta pn
        jsr setpx
        jsr drawprompt
        jmp drawkeys

drawpanel:
        jsr setpx
        stz attr
        ldx px
        ldy #0
        jsr gotoxy
        lda #' '
        jsr putc
        lda #'_'
        ldx #38
        jsr putn
        lda #' '
        jsr putc
        jsr drawtitle
        lda #1
        sta row
@sb:    ldx px
        ldy row
        jsr gotoxy
        lda #$40
        sta attr
        lda #$5A
        jsr putc
        lda px
        clc
        adc #39
        sta cx
        lda #$5F
        jsr putc
        stz attr
        inc row
        lda row
        cmp #21
        bne @sb
        ldx px
        inx
        ldy #1
        jsr gotoxy
        jsr iskegs
        beq @ph
        PRINT s_khdr
        bra @phd
@ph:    PRINT s_hdr
@phd:
        ldx px
        inx
        ldy #19
        jsr gotoxy
        lda #'_'
        ldx #38
        jsr putn
        ldx px
        ldy #21
        jsr gotoxy
        lda #' '
        jsr putc
        lda #$40
        sta attr
        lda #$4C
        ldx #38
        jsr putn
        stz attr
        lda #' '
        jsr putc
        jsr drawfree
        jsr drawfiles
        jmp drawinfo

drawtitle:
        jsr pathptr
        lda (ptr)
        sta tlen
        ldy #1
        sty tstart
        cmp #35
        bcc @fit
        sec
        sbc #30
        sta tstart
        lda #34
@fit:   sta tshow
        lda #38
        sec
        sbc tshow
        lsr a
        clc
        adc px
        tax
        ldy #0
        jsr gotoxy
        stz attr
        lda pn
        cmp cp
        bne :+
        lda #$80
        sta attr
:       lda #' '
        jsr putc
        lda tlen
        cmp #35
        bcc :+
        lda #'.'
        jsr putc
        jsr putc
        jsr putc
:       ldy tstart
@l:     lda (ptr),y
        jsr putc
        cpy tlen
        iny
        bcc @l
        lda #' '
        jsr putc
        stz attr
        rts

drawfree:
        jsr setpx
        jsr iskegs
        beq :+
        jmp kfree
:
        lda px
        clc
        adc #6
        tax
        ldy #21
        jsr gotoxy
        stz attr
        lda #' '
        jsr putc
        ldx pn
        lda pfreel,x
        sta num
        lda pfreeh,x
        sta num+1
        stz num+2
        jsr num2str
        lda #5
        jsr prnum
        PRINT s_freeof
        ldx pn
        lda ptotl,x
        sta num
        lda ptoth,x
        sta num+1
        stz num+2
        jsr num2str
        lda #5
        jsr prnum
        PRINT s_blocks
        rts

drawfiles:
        jsr setpx
        stz frow
@l:     ldx pn
        lda ptop,x
        clc
        adc frow
        sta fidx
        jsr drawfrow
        inc frow
        lda frow
        cmp #NROWS
        bne @l
        rts

drawfrow:
        ldx px
        inx
        lda frow
        clc
        adc #FROW
        tay
        jsr gotoxy
        stz attr
        ldx pn
        lda fidx
        cmp pcount,x
        bcc @have
        lda #' '
        ldx #38
        jmp putn
@have:  jsr lentptr
        ldx pn
        cpx cp
        bne @nc
        lda fidx
        cmp pcur,x
        bne @nc
        lda #$80
        sta attr
@nc:    jsr iskegs
        beq :+
        jmp kdrawrow
:       ldy #E_TAG
        lda (ep),y
        beq @nt
        lda attr
        sta sattr
        lda #$40
        sta attr
        lda #$44
        bit sattr
        bpl :+
        lda #$45
:       jsr putc
        lda sattr
        sta attr
        bra @name
@nt:    lda #' '
        jsr putc
@name:  jsr prname15
        ldy #E_STOR             ; after the name: '*' locked (like CATALOG),
        lda (ep),y              ; '+' extended (forked) file
        cmp #$FF
        beq @nl
        ldx #'+'
        cmp #$50
        beq :+
        ldx #' '
:       ldy #E_ACC
        lda (ep),y
        bmi :+
        ldx #'*'
:       txa
        bra @pl
@nl:    lda #' '
@pl:    jsr putc
        ldy #E_STOR
        lda (ep),y
        cmp #$FF
        bne @norm
        PRINT s_uprow
        stz attr
        rts
@norm:  ldy #E_TYPE
        lda (ep),y
        jsr prtype
        lda #' '
        jsr putc
        ldy #E_BLKS
        lda (ep),y
        sta num
        iny
        lda (ep),y
        sta num+1
        stz num+2
        jsr num2str
        lda #5
        jsr prnum
        lda #' '
        jsr putc
        jsr prdate
        lda #' '
        jsr putc
        jsr putc
        stz attr
        rts

; entry name padded to 15
prname15:
        lda (ep)
        sta tmp
        ldy #1
@l:     tya
        cmp tmp
        beq @ch
        bcs @sp
@ch:    lda (ep),y
        bra @pc
@sp:    lda #' '
@pc:    jsr putc
        iny
        cpy #16
        bne @l
        rts

drawinfo:
        jsr setpx
        ldx px
        inx
        ldy #20
        jsr gotoxy
        stz attr
        ldx pn
        lda pntag,x
        beq @cur
        ; summary of tagged files
        stz num
        stz num+1
        stz num+2
        stz cnt
@sl:    ldx pn
        lda cnt
        cmp pcount,x
        bcs @sd
        jsr lentptr
        ldy #E_TAG
        lda (ep),y
        beq @sn
        clc
        ldy #E_EOF
        lda (ep),y
        adc num
        sta num
        iny
        lda (ep),y
        adc num+1
        sta num+1
        iny
        lda (ep),y
        adc num+2
        sta num+2
@sn:    inc cnt
        bra @sl
@sd:    lda #' '
        jsr putc
        jsr num2str
        lda #8
        jsr prnum
        PRINT s_bytesin
        ldx pn
        lda pntag,x
        jsr prdec
        PRINT s_tagged
        jmp fillrest
@cur:   jsr iskegs
        beq :+
        jmp kinfo
:       lda pcount,x
        beq fillrest
        lda pcur,x
        jsr lentptr
        lda #' '
        jsr putc
        jsr prname15
        lda #' '
        jsr putc
        ldy #E_STOR
        lda (ep),y
        cmp #$FF
        bne :+
        PRINT s_updir
        bra fillrest
:       ldy #E_TYPE
        lda (ep),y
        cmp #$0F
        bne :+
        PRINT s_subdir
        bra @dt
:       ldy #E_EOF
        lda (ep),y
        sta num
        iny
        lda (ep),y
        sta num+1
        iny
        lda (ep),y
        sta num+2
        jsr num2str
        lda #8
        jsr prnum
@dt:    lda #' '
        jsr putc
        jsr prdate
fillrest:
        stz attr
@l:     lda cx
        sec
        sbc px
        cmp #39
        bcs @d
        lda #' '
        jsr putc
        bra @l
@d:     rts

drawprompt:
        GOTO 0,22
        stz attr
        lda pn
        pha
        lda cp
        sta pn
        jsr pathptr
        pla
        sta pn
        lda #76
        jsr pstr
        lda #'>'
        jsr putc
        lda #$80
        sta attr
        lda #' '
        jsr putc
        stz attr
@f:     lda cx
        cmp #80
        bcs @d
        lda #' '
        jsr putc
        bra @f
@d:     rts

drawkeys:
        SETPTR ttl, keylab
        ldx cp
        lda pmode,x
        beq :+
        SETPTR ttl, kkeylab
:       GOTO 0,23
        ldx #0
@l:     stz attr
        cpx #9
        bne @one
        lda #'1'
        jsr putc
        lda #'0'
        jsr putc
        bra @lab
@one:   txa
        clc
        adc #'1'
        jsr putc
@lab:   lda #$80
        sta attr
        stx tmp
        txa
        asl a
        adc tmp
        asl a
        tay
        lda #6
        sta tmp2
@c:     lda (ttl),y
        jsr putc
        iny
        dec tmp2
        bne @c
        stz attr
        cpx #9
        beq @n
        lda #' '
        jsr putc
@n:     inx
        cpx #10
        bne @l
        rts

;====================================================================
; Dialogs
;====================================================================
dlgbox_q:
        lda #<t_quit
        ldy #>t_quit
dlgbox: pha
        lda #12
        sta bl
        lda #67
        sta br
        lda #7
        sta bt
        lda #15
        sta bb
        pla
; box with title A/Y at bl..br / bt..bb
box:    sta ttl
        sty ttl+1
        stz attr
        lda br
        sec
        sbc bl
        dec a
        sta bw
        ldx bl
        ldy bt
        jsr gotoxy
        lda #' '
        jsr putc
        lda #'_'
        ldx bw
        jsr putn
        lda #' '
        jsr putc
        lda bt
        inc a
        sta row
@m:     ldx bl
        ldy row
        jsr gotoxy
        lda #$40
        sta attr
        lda #$5A
        jsr putc
        stz attr
        lda #' '
        ldx bw
        jsr putn
        lda #$40
        sta attr
        lda #$5F
        jsr putc
        stz attr
        inc row
        lda row
        cmp bb
        bne @m
        ldx bl
        ldy bb
        jsr gotoxy
        lda #' '
        jsr putc
        lda #$40
        sta attr
        lda #$4C
        ldx bw
        jsr putn
        stz attr
        lda #' '
        jsr putc
        ldy #0
:       lda (ttl),y
        beq :+
        iny
        bra :-
:       sty tlen
        lda bw
        sec
        sbc tlen
        lsr a
        clc
        adc bl
        tax
        ldy bt
        jsr gotoxy
        lda #$80
        sta attr
        lda #' '
        jsr putc
        lda ttl
        ldy ttl+1
        jsr puts
        lda #' '
        jsr putc
        stz attr
        rts

; line editor for inbuf at row 11, col 14
input:
@draw:  GOTO 14,11
        stz attr
        SETPTR ptr, inbuf
        lda #49
        jsr pstr
        lda #$80
        sta attr
        lda #' '
        jsr putc
        stz attr
@f:     lda cx
        cmp #64
        bcs @k
        lda #' '
        jsr putc
        bra @f
@k:     jsr getkey
        cmp #$0D
        beq @ok
        cmp #$1B
        beq @esc
        cmp #$7F
        beq @bs
        cmp #$08
        beq @bs
        cmp #$18
        beq @clr
        cmp #' '
        bcc @k
        cmp #'a'
        bcc @a
        cmp #'z'+1
        bcs @a
        and #$DF
@a:     ldx inbuf
        cpx #64
        bcs @k
        inx
        sta inbuf,x
        stx inbuf
        bra @draw
@bs:    lda inbuf
        beq @k
        dec inbuf
        bra @draw
@clr:   stz inbuf
        bra @draw
@ok:    clc
        rts
@esc:   sec
        rts

; Y / Return -> C=1 ; N / Esc -> C=0
yesno:  jsr getkey
        and #$DF
        cmp #'Y'
        beq @y
        cmp #$0D
        beq @y
        cmp #'N'
        beq @n
        cmp #$1B
        beq @n
        bra yesno
@y:     sec
        rts
@n:     clc
        rts

showerr:
        sta errcode
        lda #<t_error
        ldy #>t_error
        jsr dlgbox
        GOTO 14,10
        lda errcode
        cmp #$E0
        bcs @c
        PRINT s_prodos
        lda errcode
        jsr prhex
        PRINT s_colon
@c:     ldx #0
@l:     lda errtab,x
        beq @unk
        cmp errcode
        beq @f
        inx
        inx
        inx
        bra @l
@f:     lda errtab+1,x
        ldy errtab+2,x
        jsr puts
        bra @w
@unk:   PRINT s_unknown
@w:     GOTO 14,13
        PRINT s_anykey
        jsr getkey
        rts

;====================================================================
; Low level text output (direct 80-column screen writes)
;====================================================================
cls:    ldx #23
@r:     lda rowlo,x
        sta scrp
        lda rowhi,x
        sta scrp+1
        ldy #39
        lda #$A0
@c:     sta (scrp),y
        sta TXTPAGE2
        sta (scrp),y
        sta TXTPAGE1
        dey
        bpl @c
        dex
        bpl @r
        rts

gotoxy: stx cx
        sty cy
        rts

; print char A at cx,cy with attr ; preserves X,Y
putc:   phy
        bit attr
        bvs @st
        bmi @inv
        ora #$80
        bra @st
@inv:   cmp #$40
        bcc @st
        cmp #$60
        bcs @st
        and #$3F
@st:    pha
        ldy cy
        lda rowlo,y
        sta scrp
        lda rowhi,y
        sta scrp+1
        lda cx
        lsr a
        tay
        pla
        bcs @main
        sta TXTPAGE2
        sta (scrp),y
        sta TXTPAGE1
        bra @adv
@main:  sta (scrp),y
@adv:   inc cx
        ply
        rts

; print zero-terminated string A/Y ; byte $01 = Open-Apple glyph
puts:   sta sptr
        sty sptr+1
@l:     lda (sptr)
        beq @d
        cmp #1
        bne @n
        lda attr
        pha
        lda #$40
        sta attr
        lda #$41
        jsr putc
        pla
        sta attr
        bra @i
@n:     jsr putc
@i:     inc sptr
        bne @l
        inc sptr+1
        bra @l
@d:     rts

; print A, X times
putn:   cpx #0
        beq @d
@l:     jsr putc
        dex
        bne @l
@d:     rts

; print length-prefixed string at (ptr), at most A chars (shows tail)
pstr:   sta tmp2
        lda (ptr)
        beq @d
        sta tlen
        ldy #1
        cmp tmp2
        bcc @l
        beq @l
        sbc tmp2
        tay
        iny
@l:     lda (ptr),y
        jsr putc
        cpy tlen
        iny
        bcc @l
@d:     rts

prhex:  pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @nib
        pla
        and #$0F
@nib:   cmp #10
        bcc :+
        adc #6
:       adc #'0'
        jmp putc

; num (24 bit) -> numbuf (8 chars, right aligned)
num2str:
        ldx #7
@l:     jsr div10
        ora #'0'
        sta numbuf,x
        dex
        lda num
        ora num+1
        ora num+2
        bne @l
@sp:    txa
        bmi @d
        lda #' '
        sta numbuf,x
        dex
        bra @sp
@d:     rts

div10:  lda #0
        ldy #24
@l:     asl num
        rol num+1
        rol num+2
        rol a
        cmp #10
        bcc :+
        sbc #10
        inc num
:       dey
        bne @l
        rts

; print last A chars of numbuf
prnum:  sta tmp
        lda #8
        sec
        sbc tmp
        tax
@l:     lda numbuf,x
        jsr putc
        inx
        cpx #8
        bne @l
        rts

; print A as decimal without padding
prdec:  sta num
        stz num+1
        stz num+2
        jsr num2str
        ldx #0
@l:     lda numbuf,x
        cmp #' '
        bne @p
        inx
        bra @l
@p:     lda numbuf,x
        jsr putc
        inx
        cpx #8
        bne @p
        rts

; 2 digit decimal (0..99)
pr2d:   ldx #'0'
@l:     cmp #10
        bcc @d
        sbc #10
        inx
        bra @l
@d:     pha
        txa
        jsr putc
        pla
        ora #'0'
        jmp putc

; modification date of (ep) as DD-MMM-YY (9 chars)
prdate: ldy #E_MDATE
        lda (ep),y
        sta tmp
        iny
        lda (ep),y
        sta tmp2
        ora tmp
        bne @ok
        PRINT s_nodate
        rts
@ok:    lda tmp
        and #$1F
        jsr pr2d
        lda #'-'
        jsr putc
        lda tmp
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        sta dtmp
        lda tmp2
        and #1
        asl a
        asl a
        asl a
        ora dtmp
        beq @bad
        cmp #13
        bcs @bad
        dec a
        sta dtmp
        asl a
        adc dtmp
        tax
        lda months,x
        jsr putc
        lda months+1,x
        jsr putc
        lda months+2,x
        jsr putc
        bra @yr
@bad:   lda #'?'
        jsr putc
        jsr putc
        jsr putc
@yr:    lda #'-'
        jsr putc
        lda tmp2
        lsr a
@y:     cmp #100
        bcc :+
        sbc #100
        bra @y
:       jmp pr2d

; file type name (3 chars)
prtype: sta tmp
        ldx #0
@l:     lda typtab,x
        cmp tmp
        beq @f
        inx
        inx
        inx
        inx
        cpx #NTYPES*4
        bne @l
        lda #'$'
        jsr putc
        lda tmp
        jmp prhex
@f:     lda typtab+1,x
        jsr putc
        lda typtab+2,x
        jsr putc
        lda typtab+3,x
        jmp putc

getkey: lda KBD
        bpl getkey
        sta KBDSTRB
        and #$7F
        sta key
        lda OAPPLE
        sta oakey
        lda key
        rts

;====================================================================
; KEGS disk images (only when running in the KEGS emulator)
;
; KEGS (github.com/udiweinstein/kegs) lets programs list the disk
; images in the host's disk images folder and insert / eject them.
; The call is the 3 bytes $42,$EA,$D8 with A = command and X/Y =
; parameter block.  It is safe on every machine and emulator:
;  - real 65C02 / 65816: $42,$EA is a 2-byte NOP, then CLD
;  - official KEGS and GSplus: "WDM $EA,xx" is their detection code,
;    ignored without error (other WDM codes stop them in the debugger)
;  - other 65C02 emulators: $42 is a 2-byte NOP
; Only Udi's KEGS answers 'K', so only there the KEGS options appear.
; A panel in "KEGS mode" (pmode,x = 1) shows the images; its path is
; "KEGS:/" or "KEGS:/SUBFOLDER".  Entries use KEGS's 32-byte layout:
; +0 kind (1 folder, 2 image, 3 = ".."), +1 drive it is in ($61 =
; slot 6 drive 1), +2,+3 size in KB, +4 name length, +5.. name,
; +31 the slot the image belongs in (6 = 5.25", 5 = 3.5", 7 = hard disk).
;====================================================================
K_ID        = 0
K_LIST      = 1
K_MOUNT     = 2
K_EJECT     = 3
K_DRIVES    = 4
KROOTLEN    = 6                 ; "KEGS:/"
KDRVBUF     = COPYBUF           ; DRIVES result (12 x 32 bytes)
KLISTBUF    = COPYBUF+$1000     ; scratch LIST before MOUNT

.macro KEGSCALL cmd
        lda #cmd
        ldx #<kblk
        ldy #>kblk
        .byte $42, $EA, $D8
.endmacro

; At start: is KEGS there?  Also find the drive YANC runs from (kprot)
kdetect:
        stz kegs
        stz kprot
        lda #K_ID
        .byte $42, $EA, $D8
        cmp #'K'
        bne @r
        lda #1
        sta kegs
        ; volume of the start directory (path0 holds it now) -> unit
        stz pn
        jsr getvolname
        ldx #0
@v:     cpx vn
        beq @r
        ldy vl,x
        jsr cmpvol
        beq @f
        inx
        bra @v
@f:     ldy vl,x
        lda onbuf,y             ; DSSS0000 -> slot*16 + drive (1..2)
        lsr a
        lsr a
        lsr a
        lsr a
        and #7
        asl a
        asl a
        asl a
        asl a
        sta kprot
        lda onbuf,y
        asl a                   ; C = D
        lda #1
        adc #0
        ora kprot
        sta kprot
@r:     rts

; Z=0 (A=1) if panel pn is in KEGS mode
iskegs: ldx pn
        lda pmode,x
        rts

; path(pn) = "KEGS:/"
kroot:  jsr pathptr
        ldy #KROOTLEN
:       lda s_kroot-1,y
        sta (ptr),y
        dey
        bne :-
        lda #KROOTLEN
        sta (ptr)
        rts

; sub-folder of path(pn) -> kblk+3 (length) and kblk+4..
ksetsub:
        jsr pathptr
        lda (ptr)
        sec
        sbc #KROOTLEN
        bcs :+
        lda #0
:       sta kblk+3
        ldx #0
        ldy #KROOTLEN+1
@c:     cpx kblk+3
        beq @d
        lda (ptr),y
        sta kblk+4,x
        iny
        inx
        bra @c
@d:     rts

; 1 if panel pn shows a sub-folder (so entry 0 is "..")
khasup: jsr pathptr
        lda (ptr)
        cmp #KROOTLEN+1
        lda #0
        rol a
        rts

; read the disk images of panel pn
kloaddir:
        ldx pn
        stz pcount,x
        stz ptop,x
        stz pcur,x
        stz pntag,x
        jsr ksetsub
        jsr khasup
        beq @noup
        lda #0
        jsr entptr
        ldy #31
        lda #0
:       sta (ep),y
        dey
        bpl :-
        lda #3
        sta (ep)
        ldy #4
        lda #2
        sta (ep),y
        lda #'.'
        iny
        sta (ep),y
        iny
        sta (ep),y
        ldx pn
        inc pcount,x
@noup:  ldx pn
        lda pcount,x
        jsr entptr
        lda ep
        sta kblk
        lda ep+1
        sta kblk+1
        ldx pn
        lda #MAXENT
        sec
        sbc pcount,x
        sta kblk+2
        KEGSCALL K_LIST
        bcs @err
        ldx pn
        clc
        adc pcount,x
        sta pcount,x
        jmp sortpanel           ; (KEGS panels: identity order only)
@err:   lda #ERR_KFOLDER
        jsr showerr
        jmp sortpanel

; keys in a KEGS panel
kmain_key:
        ldy #0
@l:     lda ktab,y
        beq @other
        cmp key
        beq @hit
        iny
        bra @l
@hit:   tya
        asl a
        tax
        jmp (kjmp,x)
@other: lda key
        cmp #'a'
        bcc @u
        cmp #'z'+1
        bcs @u
        and #$DF
@u:     cmp #'A'
        bcc @no
        cmp #'Z'+1
        bcs @no
        sta key
        jmp k_search
@no:    jmp main_key

ktab:   .byte $0A,$0B,$08,$15,$09,$0D,$1B,$7F,'1','2','8','0',$12,$13,0
kjmp:   .word k_down,k_up,k_pgup,k_pgdn,k_tab,k_kenter,k_kparent,k_kparent
        .word k_help,k_vol,k_keject,k_quit,k_reread,k_swap

; first letter of the entry at ep, upper case (for A..Z search)
firstch:
        jsr iskegs
        bne @k
        ldy #1
        lda (ep),y
        rts
@k:     ldy #5
        lda (ep),y
        cmp #'a'
        bcc :+
        cmp #'z'+1
        bcs :+
        and #$DF
:       rts

; Return: folder -> enter it, ".." -> parent, image -> insert box
k_kenter:
        ldx pn
        lda pcount,x
        bne :+
        jmp main_key
:       lda pcur,x
        jsr lentptr
        lda (ep)
        cmp #3
        beq k_kparent
        cmp #1
        beq @dir
        jmp kinsert
@dir:   jsr pathptr
        lda (ptr)
        sta tmp
        ldy #4
        lda (ep),y
        sta tmp2
        sec
        adc tmp                 ; path + "/" + name
        cmp #64
        bcs @long
        ldy tmp
        lda tmp
        cmp #KROOTLEN
        beq @nos                ; "KEGS:/" already ends with '/'
        iny
        lda #'/'
        sta (ptr),y
@nos:   ldx #0
@n:     phy
        txa
        clc
        adc #5
        tay
        lda (ep),y
        ply
        iny
        sta (ptr),y
        inx
        cpx tmp2
        bne @n
        tya
        sta (ptr)
        jsr loaddir
        jmp main_redraw
@long:  lda #ERR_LONG
        jsr showerr
        jmp main_redraw

; Esc / Delete: parent folder, cursor on the folder we came from
k_kparent:
        jsr pathptr
        lda (ptr)
        cmp #KROOTLEN+1
        bcs :+
        jmp main_key
:       tay
@l:     lda (ptr),y
        cmp #'/'
        beq @f
        dey
        bra @l
@f:     sty tmp                 ; kname = part after the last '/'
        lda (ptr)
        sec
        sbc tmp
        sta kname
        ldx #0
@c:     iny
        lda (ptr),y
        sta kname+1,x
        inx
        cpx kname
        bne @c
        ldy tmp
        cpy #KROOTLEN
        beq :+
        dey                     ; drop the '/' (keep it after "KEGS:")
:       tya
        sta (ptr)
        jsr loaddir
        stz cnt                 ; find kname
@s:     ldx pn
        lda cnt
        cmp pcount,x
        bcs @d
        jsr lentptr
        ldy #4
        lda (ep),y
        cmp kname
        bne @nx
        tax
@cc:    txa
        clc
        adc #4
        tay
        lda (ep),y
        cmp kname,x
        bne @nx
        dex
        bne @cc
        ldx pn
        lda cnt
        sta pcur,x
        jsr fixtop
        bra @d
@nx:    inc cnt
        bra @s
@d:     jmp main_redraw

; KEGS's entry number of the cursor entry (minus the ".." row) -> A
kapiidx:
        jsr khasup
        sta tmp
        ldx pn
        lda pcur,x
        sec
        sbc tmp
        rts

; Return on an image: choose the drive and insert it
kinsert:
        lda #<KDRVBUF
        sta kblk
        lda #>KDRVBUF
        sta kblk+1
        KEGSCALL K_DRIVES
        ; drives offered: D1 and D2 of the image's slot (6 = 5.25",
        ; 5 = 3.5", 7 = hard disk); if KEGS didn't say, all of them
        ldy #31
        lda (ep),y
        cmp #5
        bcc @all
        cmp #8
        bcs @all
        sec
        sbc #5
        asl a                   ; DRIVES entry of drive 1
        sta kopt
        inc a
        sta kopt+1
        lda #2
        bra @nopt
@all:   ldx #5
:       lda kalltab,x
        sta kopt,x
        dex
        bpl :-
        lda #6
@nopt:  sta knopt
        lda #$FF                ; first drive that isn't YANC's
@fs:    inc a
        jsr kprotopt
        beq @fs
        sta ksel
        lda #18
        sta bl
        lda #61
        sta br
        lda #5
        sta bt
        lda knopt
        clc
        adc #11
        sta bb
        lda #<t_insert
        ldy #>t_insert
        jsr box
        GOTO 21,6               ; image name
        jsr kname27
@draw:  ldx #0
@o:     phx
        txa
        clc
        adc #8
        tay
        ldx #20
        jsr gotoxy
        plx
        stz attr
        cpx ksel
        bne :+
        lda #$80
        sta attr
:       lda #' '
        jsr putc
        jsr kdrvent             ; ptr2 = DRIVES entry of option X
        lda (ptr2)
        jsr prdrive
        lda #' '
        jsr putc
        jsr putc
        lda (ptr2)
        cmp kprot
        bne :+
        PRINT s_kyanc
        bra @pad
:       ldy #1
        lda (ptr2),y
        bne :+
        PRINT s_kempty
        bra @pad
:       lda ptr2
        sta ptr
        lda ptr2+1
        sta ptr+1
        lda #30
        jsr knamep              ; name at (ptr)+4, at most 30 chars
@pad:   lda cx
        cmp #59
        bcs :+
        lda #' '
        jsr putc
        bra @pad
:       stz attr
        inx
        cpx knopt
        bne @o
        lda knopt
        clc
        adc #9
        tay
        ldx #21
        jsr gotoxy
        PRINT s_kins
@k:     jsr getkey
        cmp #$0A
        beq @dn
        cmp #$15
        beq @dn
        cmp #$0B
        beq @up
        cmp #$08
        beq @up
        cmp #$0D
        beq @go
        cmp #$1B
        bne @k
        jmp main_redraw
@dn:    lda ksel
@dn2:   inc a
        cmp knopt
        bcs @k
        jsr kprotopt
        beq @dn2
        sta ksel
        jmp @draw
@up:    lda ksel
@up2:   dec a
        bmi @k
        jsr kprotopt
        beq @up2
        sta ksel
        jmp @draw
@go:    ; LIST again (another panel may have listed meanwhile), then MOUNT
        jsr ksetsub
        lda #<KLISTBUF
        sta kblk
        lda #>KLISTBUF
        sta kblk+1
        lda #MAXENT
        sta kblk+2
        KEGSCALL K_LIST
        jsr kapiidx
        sta kblk
        ldx ksel
        jsr kdrvent
        lda (ptr2)
        sta kblk+1
        lda kprot
        sta kblk+2
        KEGSCALL K_MOUNT
        bcc kopen
        lda #ERR_KMOUNT
        jsr showerr
kdone:  jsr reloadboth
        jmp main_redraw

; After inserting: show the disk itself in this panel, if ProDOS sees it
; there (A = drive used, slot*16 + drive).  Otherwise (DOS 3.3 disk,
; or a hard disk ProDOS maps elsewhere) stay in the images list.
kopen:  pha
        and #$70                ; ProDOS unit DSSS0000
        sta tmp
        pla
        and #$0F
        cmp #2
        bne :+
        lda tmp
        ora #$80
        sta tmp
:       jsr scanvols
        ldx #0
@v:     cpx vn
        beq kdone
        ldy vl,x
        lda onbuf,y
        and #$F0
        cmp tmp
        beq @f
        inx
        bra @v
@f:     lda cp
        sta pn
        tax
        stz pmode,x             ; back to a ProDOS panel
        jsr setvol
        jsr loaddir
        lda cp                  ; other panel: refresh
        eor #1
        sta pn
        jsr reloadkeep
        lda cp
        sta pn
        jmp main_redraw

; Z=1 if option A is the drive YANC runs from (keeps A)
kprotopt:
        pha
        cmp knopt
        bcs @n
        tax
        jsr kdrvent
        lda (ptr2)
        cmp kprot
        beq @y
@n:     pla
        ldx #1                  ; Z=0
        rts
@y:     pla
        ldx #0                  ; Z=1
        rts

; ptr2 = DRIVES entry for insert option X
kdrvent:
        lda kopt,x
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<KDRVBUF
        sta ptr2
        lda #>KDRVBUF
        adc #0
        sta ptr2+1
        rts
kalltab:.byte 2, 3, 0, 1, 4, 5               ; S6D1 S6D2 S5D1 S5D2 S7D1 S7D2

; 8: eject the image under the cursor
k_keject:
        ldx pn
        lda pcount,x
        bne :+
@no:    jmp main_key
:       lda pcur,x
        jsr lentptr
        lda (ep)
        cmp #2
        bne @no
        ldy #1
        lda (ep),y
        beq @no                 ; not in a drive
        cmp kprot
        bne :+
        lda #ERR_KPROT
        jsr showerr
        jmp main_redraw
:       sta kblk+1
        lda #<t_eject
        ldy #>t_eject
        jsr dlgbox
        GOTO 14,9
        PRINT s_keject
        GOTO 14,10
        jsr kname27
        GOTO 14,11
        PRINT s_kfrom
        ldy #1
        lda (ep),y
        jsr prdrive
        GOTO 14,13
        PRINT s_yn
        jsr yesno
        bcs :+
        jmp main_redraw
:       KEGSCALL K_EJECT
        jmp kdone

; print the name of entry ep (at most 27 chars)
kname27:
        lda ep
        sta ptr
        lda ep+1
        sta ptr+1
        lda #26
; print the name at (ptr)+4 (length) / +5.., at most A chars
knamep: sta tmp2
        ldy #4
        lda (ptr),y
        cmp tmp2
        bcc :+
        lda tmp2
:       sta tmp
        beq @d
        ldy #5
@l:     lda (ptr),y
        jsr putc
        iny
        dec tmp
        bne @l
@d:     rts

; print drive A (slot*16 + drive) as "S6,D1"
prdrive:
        pha
        lda #'S'
        jsr putc
        pla
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        ora #'0'
        jsr putc
        lda #','
        jsr putc
        lda #'D'
        jsr putc
        pla
        and #$0F
        ora #'0'
        jmp putc

; a row of a KEGS panel (entry ep): name, size, drive
kdrawrow:
        lda #' '
        jsr putc
        lda ep
        sta ptr
        lda ep+1
        sta ptr+1
        lda cx
        clc
        adc #22                 ; column where the size starts
        pha
        lda #21
        jsr knamep
        pla
        sta dtmp
@sp:    lda cx
        cmp dtmp
        bcs :+
        lda #' '
        jsr putc
        bra @sp
:       lda (ep)
        cmp #2
        beq @img
        cmp #1
        beq @dir
        PRINT s_kup
        bra @end
@dir:   PRINT s_kdir
        bra @end
@img:   jsr ksize
        lda #' '
        jsr putc
        ldy #1
        lda (ep),y
        beq @end
        jsr prdrive
@end:   jmp kfill

; size of entry ep: "  140K", " 32M" for 10 MB or more
ksize:  ldy #2
        lda (ep),y
        sta num
        iny
        lda (ep),y
        sta num+1
        stz num+2
        cmp #>10240
        bcc @k
        ldx #10                 ; KB -> MB
:       lsr num+1
        ror num
        dex
        bne :-
        jsr num2str
        lda #5
        jsr prnum
        lda #'M'
        jmp putc
@k:     jsr num2str
        lda #5
        jsr prnum
        lda #'K'
        jmp putc

; fill the rest of the panel row with spaces
kfill:  lda cx
        sec
        sbc px
        cmp #39
        bcs @d
        lda #' '
        jsr putc
        bra kfill
@d:     stz attr
        rts

; info line of a KEGS panel
kinfo:  lda pcount,x
        bne :+
        jmp fillrest
:       lda pcur,x
        jsr lentptr
        lda #' '
        jsr putc
        lda ep
        sta ptr
        lda ep+1
        sta ptr+1
        lda #20
        jsr knamep
@sp:    lda cx
        sec
        sbc px
        cmp #22
        bcs :+
        lda #' '
        jsr putc
        bra @sp
:       lda (ep)
        cmp #2
        bne @d
        jsr ksize
        ldy #1
        lda (ep),y
        beq @d
        PRINT s_kin
        ldy #1
        lda (ep),y
        jsr prdrive
@d:     jmp fillrest

; bottom line of a KEGS panel (instead of free blocks)
kfree:  lda px
        clc
        adc #6
        tax
        ldy #21
        jsr gotoxy
        stz attr
        PRINT s_kfoot
        rts

; Copy to a KEGS panel is not possible: show why and go back
kchkdst:
        lda cp
        eor #1
        tax
        lda pmode,x
        bne :+
        rts
:       pla
        pla
        lda #ERR_KDST
        jsr showerr
        jmp main_redraw

;====================================================================
; Data
;====================================================================
        .rodata
rowlo:
        .repeat 24, I
        .byte <($0400 + (I .mod 8) * $80 + (I / 8) * $28)
        .endrepeat
rowhi:
        .repeat 24, I
        .byte >($0400 + (I .mod 8) * $80 + (I / 8) * $28)
        .endrepeat

months: .byte "JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC"

typtab: .byte $00,"   "
        .byte $01,"BAD"
        .byte $04,"TXT"
        .byte $06,"BIN"
        .byte $08,"FOT"
        .byte $0F,"DIR"
        .byte $19,"ADB"
        .byte $1A,"AWP"
        .byte $1B,"ASP"
        .byte $B0,"SRC"
        .byte $B3,"S16"
        .byte $C0,"PNT"
        .byte $C1,"PIC"
        .byte $E0,"LBR"
        .byte $EF,"PAS"
        .byte $F0,"CMD"
        .byte $FA,"INT"
        .byte $FB,"IVR"
        .byte $FC,"BAS"
        .byte $FD,"VAR"
        .byte $FE,"REL"
        .byte $FF,"SYS"
NTYPES = (* - typtab) / 4

keylab: .byte "Help  Vol   View  Lock  Copy  RenMovMkdir DeleteSort  Quit  "
kkeylab:.byte "Help  Vol                                 Eject       Quit  "
s_khdr:   .byte " Name                    Size Drive   ", 0
s_kroot:  .byte "KEGS:/"
s_kup:    .byte "  <UP>", 0
s_kdir:   .byte " <DIR>", 0
s_kyanc:  .byte "(YANC runs from here)", 0
s_kempty: .byte "(empty)", 0
s_kins:   .byte "Enter=Insert   Esc=Cancel", 0
s_keject: .byte "Eject", 0
s_kfrom:  .byte "from drive ", 0
s_kin:    .byte " in ", 0
s_kfoot:  .byte " Enter=Insert  8=Eject  Esc=Up ", 0
s_kitem:  .byte " KEGS disk images...", 0
t_insert: .byte "Insert disk", 0
t_eject:  .byte "Eject disk", 0

s_hdr:    .byte " Name", "            ", "Typ", " ", " Blks", " ", "Modified", "   ", 0
s_uprow:  .byte "   ", " ", " <UP>", " ", "         ", "  ", 0
s_updir:  .byte "  UP-DIR", 0
s_subdir: .byte " SUB-DIR", 0
s_nodate: .byte "<NO DATE>", 0
s_freeof: .byte " free of ", 0
s_blocks: .byte " blocks ", 0
s_bytesin:.byte " bytes in ", 0
s_tagged: .byte " tagged", 0
s_yn:     .byte "Proceed? (Y/N)", 0
s_anykey: .byte "Press any key", 0
s_lockq:  .byte "Lock or unlock ", 0
s_lu:     .byte "L=Lock  U=Unlock  B=Boot first  Esc=Cancel", 0
s_dotsys: .byte ".SYSTEM"
s_bootok: .byte " now starts first at boot.", 0
s_already:.byte " already starts first.", 0
s_quit:   .byte "Do you want to quit YANC?", 0
s_copy:   .byte "Copy ", 0
s_renmov: .byte "Rename or move ", 0
s_itemsto:.byte " item(s) to:", 0
s_items:  .byte " item(s)?", 0
s_delete: .byte "Delete ", 0
s_copying:.byte "Copying ", 0
s_exists: .byte "File already exists in destination.", 0
s_ovr:    .byte "Overwrite? Y=Yes N=No A=All Esc=Stop", 0
s_skipped:.byte " director(ies) skipped - not copied", 0
s_mkdir:  .byte "Create the directory:", 0
s_locked: .byte " is locked.", 0
s_dellock:.byte "Delete it anyway? (Y/N)", 0
s_prodos: .byte "ProDOS error $", 0
s_colon:  .byte ": ", 0
s_unknown:.byte "Unknown error", 0
s_view:   .byte " View: ", 0
s_bs:     .byte 12, "BASIC.SYSTEM"
s_hex:    .byte "   [HEX]", 0
s_text:   .byte "   [TEXT]", 0
s_vkeys:  .byte " Esc Exit   Space/Down Next page   Up Previous page   H Text/Hex", 0

t_copy:   .byte "Copy", 0
t_renmov: .byte "Rename/Move", 0
t_mkdir:  .byte "Make directory", 0
t_delete: .byte "Delete", 0
t_quit:   .byte "Quit", 0
t_lock:   .byte "Lock/Unlock", 0
t_boot:   .byte "Boot", 0
t_error:  .byte "Error", 0
t_note:   .byte "Note", 0
t_vol:    .byte "Choose volume", 0
t_help:   .byte "Help", 0

errtab: .byte $27
        .word e27
        .byte $28
        .word e28
        .byte $2B
        .word e2b
        .byte $2E
        .word e2e
        .byte $40
        .word e40
        .byte $42
        .word e42
        .byte $44
        .word e44
        .byte $45
        .word e45
        .byte $46
        .word e46
        .byte $47
        .word e47
        .byte $48
        .word e48
        .byte $49
        .word e49
        .byte $4A
        .word e4a
        .byte $4B
        .word e4b
        .byte $4E
        .word e4e
        .byte $50
        .word e50
        .byte $51
        .word e51
        .byte $52
        .word e52
        .byte $53
        .word e53
        .byte $55
        .word e55
        .byte $56
        .word e56
        .byte $57
        .word e57
        .byte $5A
        .word e5a
        .byte ERR_SAME
        .word ee1
        .byte ERR_NOTDIR
        .word ee2
        .byte ERR_ONE
        .word ee3
        .byte ERR_NOTEMPTY
        .word ee4
        .byte ERR_LONG
        .word ee5
        .byte ERR_NOVOL
        .word ee6
        .byte ERR_NOBS
        .word ee7
        .byte ERR_BOOT
        .word ee8
        .byte ERR_KFOLDER
        .word ee9
        .byte ERR_KDST
        .word eea
        .byte ERR_KMOUNT
        .word eeb
        .byte ERR_KPROT
        .word eec
        .byte 0

e27:    .byte "I/O error", 0
e28:    .byte "No device connected", 0
e2b:    .byte "Disk is write-protected", 0
e2e:    .byte "Disk was switched", 0
e40:    .byte "Invalid pathname", 0
e42:    .byte "Too many files open", 0
e44:    .byte "Directory not found", 0
e45:    .byte "Volume not found", 0
e46:    .byte "File not found", 0
e47:    .byte "Duplicate filename", 0
e48:    .byte "Disk full", 0
e49:    .byte "Directory full", 0
e4a:    .byte "Incompatible file format", 0
e4b:    .byte "Unsupported storage type", 0
e4e:    .byte "Access denied (locked)", 0
e50:    .byte "File is open", 0
e51:    .byte "Directory damaged", 0
e52:    .byte "Not a ProDOS disk", 0
e53:    .byte "Invalid parameter", 0
e55:    .byte "Too many volumes", 0
e56:    .byte "Bad buffer address", 0
e57:    .byte "Duplicate volume name", 0
e5a:    .byte "Volume bitmap damaged", 0
ee1:    .byte "Source and destination are the same", 0
ee2:    .byte "Destination is not a directory", 0
ee3:    .byte "Plain rename needs a single item", 0
ee4:    .byte "Directory is not empty", 0
ee5:    .byte "Pathname too long", 0
ee6:    .byte "No volumes online", 0
ee7:    .byte "BASIC.SYSTEM not found", 0
ee8:    .byte "Boot: pick a *.SYSTEM file in the volume root", 0
ee9:    .byte "KEGS disk images folder not found (F4)", 0
eea:    .byte "Not possible: other panel is KEGS images", 0
eeb:    .byte "KEGS could not insert that disk image", 0
eec:    .byte "YANC is running from that drive", 0

helptab:
        .word h1,h0,h2,h3,h4,h5,h6,h7,h0,h9,h10,h11,h11b,h12,h13,h14,h15,h16,h17
        .word 0
h0:     .byte 0
h1:     .byte "YANC v1.3 - Yet Another Norton Commander for the Apple IIc", 0
h2:     .byte "Up/Down      Move cursor          ",1,"-Up/",1,"-Down  First / last", 0
h3:     .byte "Left/Right   Page up / down       Tab            Switch panel", 0
h4:     .byte "Return       Enter dir / run file Esc/Delete     Parent directory", 0
h5:     .byte "Space        Tag / untag          A..Z           Jump to name", 0
h6:     .byte "+  -  *      Tag all/none/invert  Ctrl-R         Re-read disks", 0
h7:     .byte "Ctrl-S       Swap panels          2 > KEGS disk images (in KEGS)", 0
h9:     .byte "1 Help       2 Choose volume      3 View (text / hex)  4 Lock", 0
h10:    .byte "5 Copy       6 Rename / Move      7 Make directory", 0
h11:    .byte "8 Delete     9 Sort name/type     0 Quit     * locked + forked", 0
h11b:   .byte "4 then B: make the .SYSTEM file under the cursor boot first", 0
h12:    .byte "Commands work on tagged files, or on the file under the cursor.", 0
h13:    .byte "Copy / Move: to the directory shown in the other panel.", 0
h14:    .byte "Rename: press 6 and type a new name (no '/').", 0
h15:    .byte "Move to any directory: type a full path such as /HD/GAMES.", 0
h16:    .byte "Return runs SYS files; BAS and BIN run via BASIC.SYSTEM.", 0
h17:    .byte "Press any key", 0

;--------------------------------------------------------------------
; MLI parameter blocks
;--------------------------------------------------------------------
        .data
onlinep:  .byte 2, 0
          .word onbuf
openp:    .byte 3
openpath: .word 0
openbuf:  .word IOBUF1
openref:  .byte 0
open2p:   .byte 3
          .word fp2
          .word IOBUF2
open2ref: .byte 0
readp:    .byte 4
readref:  .byte 0
readbuf:  .word 0
readreq:  .word 0
readtrn:  .word 0
writep:   .byte 4
writeref: .byte 0
          .word COPYBUF
writereq: .word 0
          .word 0
closep:   .byte 1
closeref: .byte 0
gfip:     .byte $0A
gfipath:  .word 0
gfiacc:   .byte 0
gfitype:  .byte 0
gfiaux:   .word 0
gfistyp:  .byte 0
gfiblk:   .word 0
gfimd:    .word 0
gfimt:    .word 0
gficd:    .word 0
gfict:    .word 0
sfip:     .byte 7
sfipath:  .word 0
sfiacc:   .byte 0
sfitype:  .byte 0
sfiaux:   .word 0
          .byte 0, 0, 0
sfimd:    .word 0
sfimt:    .word 0
crp:      .byte 7
crpath:   .word 0
cracc:    .byte $C3
crtype:   .byte 0
craux:    .word 0
crstyp:   .byte 1
crcd:     .word 0
crct:     .word 0
desp:     .byte 1
despath:  .word 0
renp:     .byte 2
          .word fp1
          .word fp2
markp:    .byte 2
markref:  .byte 0
markpos:  .byte 0, 0, 0
pfxsetp:  .byte 1
pfxsp:    .word 0
pfxp:     .byte 1
          .word pfxbuf
blkp:     .byte 3
blkunit:  .byte 0
blkbuf:   .word 0
blkno:    .word 0
quitp:    .byte 4, 0, 0, 0, 0, 0, 0
crtp:     .byte 7               ; CREATE of a temporary file (path in inbuf)
          .word inbuf
          .byte $C3, $00
          .word 0
          .byte 1
          .word 0, 0
tdesp:    .byte 1
          .word inbuf
kname:    .res 28               ; KEGS: folder name to find after "up"
kblk:     .res 68               ; KEGS call parameter block
