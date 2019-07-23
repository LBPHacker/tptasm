; * Define this so %include "common" doesn't throw an error.
;   This needs to be done because the macro jmp needs an address
;   that is guaranteed to hold 0x1FFFFFFF.
%define _CONST_MINUS_1 const.minus_1
%include "common"

%define output 0x100

start:
    mov [.buf_c]              ; * Clear accumulator.
    mov [.buf_a]              ; * Store 0 in A.
    add [const.msb]           ; * Make it printable.
    mov [output]              ; * Print 0.
    add [const.one]
    mov [.buf_b]              ; * Store 1 in B.
    add [const.msb]           ; * Make it printable.
    add [const.one]
    mov [output]              ; * Print 1.
.loop:
    mov [.buf_c]              ; * Clear accumulator.
    add [.buf_a]              ; * Load A.
    mov [.buf_c]              ; * C = A.
    add [.buf_b]              ; * Load B.
    mov [.buf_a]              ; * A = B.
    add [.buf_b]              ; * Load B.
    add [.buf_c]              ; * Add C, which is currently A, so we have A + B.
    mov [.buf_b]              ; * B = A + B.
    add [.buf_b]              ; * Load new B.
    flip                      ; * Calculate -B-1.
    add [const.bcd_limit_p1]  ; * Compare against 10000000.
    jc .no_bail               ; * If that wasn't enough to overflow the
    jmp .done                 ;   addition, B is above 9999999, so we bail.
.no_bail:
    mov [.buf_c]              ; * Clear accumulator.
    add [.buf_b]              ; * Load new B.
    add [const.msb]           ; * Make it printable.
    mov [output]              ; * Print B.
    jmp .loop
.done:
.hlt:                         ; * "Halt".
    jmp .hlt
.buf_a:
    dw 0
.buf_b:
    dw 0
.buf_c:
    dw 0

const:
.zero:
    dw 0
.minus_1:
    dw 0x1FFFFFFF
.one:
    dw 1
.msb:
    dw 0x10000000
.bcd_limit_p1:
    dw 10000000

