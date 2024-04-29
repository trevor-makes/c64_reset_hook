#importonce
// https://codebase64.org/doku.php?id=base:ax_tinyrand8
// AX+ Tinyrand8
// A fast 8-bit random generator with an internal 16bit state
//
// Algorithm, implementation and evaluation by Wil
// This version stores the seed as arguments and uses self-modifying code
// The name AX+ comes from the ASL, XOR and addition operation
//
// Size: 15 Bytes (not counting the set_seed function)
// Execution time: 18 (without RTS)
// Period 59748

rand8: {
	lda b1:#31
	asl
	eor a1:#53
	sta b1
	adc a1
	sta a1
	rts
}

// sets the seed based on the value in A
// always sets a1 and b1 so that a cycle with maximum period is chosen
// constants 217 and 21263 have been derived by simulation
/*set_seed:
	pha
	and #217
	clc
	adc #<21263
	sta rand8.a1
	pla
	and #255-217
	adc #>21263
	sta rand8.b1
	rts*/