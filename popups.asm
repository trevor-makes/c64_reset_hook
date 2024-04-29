.label payloadDest = $8000
.label screenPage = $4
.label colorPage = $d8
.label irqVector = $314
.label breakVector = $316
.label srcPtr = $fb
.label destPtr = $fd
.label screenPtr = $fb
.label colorPtr = $fd
.label zpTemp = 2

// BASIC launcher program
    BasicUpstart2(start)
start: {
    // copy payload from end of BASIC program to $8000
    php // save interrupt mask
    sei // disable interrupts
    lda #<payloadSrc; sta srcPtr
    lda #>payloadSrc; sta srcPtr+1
    lda #<payloadDest; sta destPtr
    lda #>payloadDest; sta destPtr+1
    ldy #0
    ldx #>payloadSize
    beq copyPartial
copyPage:
    lda (srcPtr),y
    sta (destPtr),y
    iny
    bne copyPage

    // next page
    inc srcPtr+1
    inc destPtr+1
    dex
    bne copyPage

copyPartial:
    cpy #<payloadSize
    beq endCopy
    lda (srcPtr),y
    sta (destPtr),y
    iny
    bne copyPartial

endCopy:
    plp // restore interrupt mask
    // execute payload
    jmp inject

payloadSrc:
    // place relocated payload code at end of BASIC program
    .segmentout [segments = "Payload"]
    .label payloadSize = *-payloadSrc // TODO why can't I do Payload.size() or similar?
}

// payload to be copied to $8000
.segmentdef Signature [start = payloadDest]
.segmentdef Data [startAfter = "Signature"]
.segmentdef Code [startAfter = "Data"]
.segmentdef Payload [segments = "Signature,Data,Code"]

// autostart cartridge signature
.segment Signature
    .word coldStart // cold start vector
    .word restore // warm start vector
    .byte $c3,$c2,$cd,$38,$30 // CBM80

.segment Code
coldStart: {
    // mirror KERNAL reset vector from $FCEF
    stx $d016 // clear bit 5 to reset VIC-II
    jsr $fda3 // init CIA+SID
    jsr $fd50 // init RAM
    jsr $fd15 // init KERNAL vectors
    jsr initvic
    jsr inject // <- inject payload wedges
    cli
    jmp ($a000) // BASIC cold start
initvic:
    jmp ($fcfc) // $ff5b on KERNAL Rev 2-3, $e518 on Rev 1
}

restore: {
    // mirror KERNAL NMI vector from $FE5E
    jsr $f6bc // scan keyboard
    jsr $ffe1 // check for STOP key
    beq warmStart // branch to warm start
    jmp $fe72 // continue normal NMI
}

warmStart: {
    // mirror KERNAL warm start
    jsr $fd15 // init KERNAL vectors
    jsr $fda3 // init CIA+SID
    jsr $e518 // init VIC-II
    jsr inject // <- inject payload wedges
    jmp ($a002) // BASIC warm start
}

inject: {
    // adjust FRETOP and MEMSIZ to protect payload
    //lda #<payloadDest; sta $33; sta $37; sta $283 // lo byte
    lda #>payloadDest; sta $34; sta $38; sta $284 // hi byte
    // change default text color to white
    lda #WHITE; sta $286
    // reset mask for popup countdown
    lda #$ff; sta jiffyMask

    // change interrupt vectors
    php // save interrupt mask
    sei // disable interrupts
    // replace CPU break handler
    lda #<warmStart; sta breakVector
    lda #>warmStart; sta breakVector+1
    // wedge into IRQ handler
    lda #<irqWedge; sta irqVector
    lda #>irqWedge; sta irqVector+1
    plp // restore interrupt mask
    rts

irqWedge:
    // once per ~4.3 sec (LSB of jiffy clock is zero), right shift mask
    lda $a2
    bne !skip+
    lsr jiffyMask
!skip:
    // display popup when LSB of jiffy AND mask is zero
    // interval halves as mask is shifted: 4.3 sec, 2.1 sec, 1.1 sec...
    and jiffyMask:#$ff
    bne !skip+
    jsr popup
!skip:
    jmp $ea31 // normal IRQ handler
}

popup: {
    jsr rollCoords

    //.const box_top = InvertString(@"\$4f\$77\$50") // <- what I'd like to write
    .const box_top = @"\$4f\$77\$50" // ┏ ━ ┓
    .const box_mid = @"\$74\$20\$6a" // ┃   ┃
    .const box_bot = @"\$4c\$6f\$7a" // ┗ ━ ┛

    .encoding "screencode_upper"
    //.const warning = InvertString(@"\$74     WARNING!    \$6a") // <- what I'd like to write
    .const warning = @"\$74     WARNING!    \$6a"
    .const message = @"\$74 C64 IS INFECTED \$6a"
    .const width = message.size()
    .assert "RNG math hard-coded for width",width,19

    // draw popup box
    DrawBoxDecor(box_top, YELLOW, width); jsr incrementRows
    DrawBoxText(warning, YELLOW); jsr incrementRows
    DrawBoxDecor(box_mid, YELLOW, width); jsr incrementRows
    DrawBoxText(message, YELLOW); jsr incrementRows
    DrawBoxDecor(box_bot, YELLOW, width)
    rts
}

// TODO AGHHHHHHHH! Why can't I cast str.charAt(i)|$80 back to Char?????
// As written, this appends decimal strings like "244" or "-12" instead of '\$f4'
/*.function InvertString(str) {
    .var tmp = ""
    .for (var i = 0; i < str.size(); i++)
        .eval tmp += str.charAt(i) | $80 // '\$80' doesn't work either
    .return tmp
}*/

.macro DrawBoxColor(color, width) {
    ldy #width-1
    lda #color
loop:
    sta (colorPtr),y
    dey
    bpl loop
}

.macro DrawBoxDecor(str, color, width) {
    // set high bits for inverted graphics
    // TODO invert strings before passing to this macro
    .const left   = str.charAt(0) | $80
    .const middle = str.charAt(1) | $80
    .const right  = str.charAt(2) | $80

    ldy #width-1
    lda #right; sta (screenPtr),y
    dey
    lda #middle
loop:
    sta (screenPtr),y
    dey
    bne loop
    lda #left; sta (screenPtr),y

    DrawBoxColor(color, width)
}

.macro DrawBoxText(str, color) {
    .const width = str.size()

.segment Data
data: // store string with high bit set for inverted graphics
    // TODO invert strings before passing to this macro
    .fill width, str.charAt(i) | $80

.segment Code
    ldy #width-1
loop:
    lda data,y
    sta (screenPtr),y
    dey
    bpl loop

    DrawBoxColor(color, width)
}

incrementRows: {
    // increment screen row
    clc
    lda screenPtr
    adc #40 // 40 bytes per row
    sta screenPtr
    bcc !nocarry+
    inc screenPtr+1

    // increment color row
    clc
!nocarry:
    lda colorPtr
    adc #40 // 40 bytes per row
    sta colorPtr
    bcc !nocarry+
    inc colorPtr+1
!nocarry:
    rts
}

#import "tinyrand.asm"

// return random number from [0, 22) in A
// TODO make macro for N-sided die rolls
roll22: {
    // a = rand[0,22)
    //   = 22 * rand8 / 2^8
    //   = 11 * rand8 / 2^7
    //   = (((r8 >> 1 + r8) >> 2) + r8) >> 4
    jsr rand8
    lsr
    clc
    adc rand8.a1
    ror
    lsr
    clc
    adc rand8.a1
    ror
    lsr
    lsr
    lsr
    rts
}

// return 40 * random number from [0, 21) in A
// NOTE upper 2 bits (9 and 8) are packed into lower 2 bits (1 and 0)
// lower 3 bits would otherwise always be 0 since 40 = 5 * 2^3
// use AND #$F8 to get lower byte, AND $#03 to get upper byte
roll21x40: {
    // a = rand[0,21) * 8
    //   = (21 * rand8 / 2^8) * 2^3
    //   = 21 * rand8 / 2^5
    //   = (((r8 >> 2 + r8) >> 2) + r8) >> 1
    jsr rand8
    lsr
    lsr
    clc
    adc rand8.a1
    ror
    lsr
    clc
    adc rand8.a1
    ror
    and #$f8 // truncate fractional part
    // a = rand(0, 21] * 10
    //   = (rand(0,21] * 8) * 5 / 2^2
    //   = (a >> 2) + a
    sta zpTemp
    lsr
    lsr
    adc zpTemp
    // multiply by 4, rolling upper 2 bits into lower 2 bits
    cmp #$80
    rol
    cmp #$80
    rol
    rts
}

rollCoords: {
    // set row to rand[0,21) and col to rand[0,22)
    jsr roll21x40
    tax
    // add lower bytes
    and #$f8
    sta zpTemp
    jsr roll22
    clc
    adc zpTemp
    sta screenPtr
    sta colorPtr
    // add upper byte to base screen and color pages
    txa
    and #$03
    adc #0 // add carry bit from lower bytes
    tax
    adc #screenPage
    sta screenPtr+1
    txa
    adc #colorPage
    sta colorPtr+1
    rts
}