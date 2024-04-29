.file [name="%o.prg",segments="Signature,Data,Code"]

.segmentdef Signature [start=$8000]
.segmentdef Data [startAfter="Signature"]
.segmentdef Code [startAfter="Data"]

// autostart cartridge signature
.segment Signature
    .word reset // cold start vector
    .word restore // warm start vector
    .byte $c3,$c2,$cd,$38,$30 // CBM80

.segment Code
reset:
    .encoding "petscii_mixed"
    PrintString(@"\$13\$93\$0e\$05\n Trapped Reset") // home, clear, lower, white
    jmp *

restore:
    .encoding "petscii_mixed"
    PrintString(@"\$13\$93\$0e\$05\n Trapped Restore") // home, clear, lower, white
    jmp *

.macro PrintString(str) {
.segment Data
data: // store string reversed to simplify code
    .fill str.size(), str.charAt(str.size() - i - 1)

.segment Code
    ldx #str.size()
loop:
    lda data-1,x
    jsr $ffd2
    dex
    bne loop
}
