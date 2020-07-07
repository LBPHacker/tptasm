_Model "I8M7D28S"             ; * Specify target model.

%include "common"             ; * Common header built into the assembler.

start:
    ld zero                   ; * Zero out bus and add small constants to it
                              ;   later instead of storing them in RAM; this
                              ;   technique does save RAM but it only works for
                              ;   small (8-bit) constants and whatever you're
                              ;   willing to construct from those.
    addi 0x0F    | stl        ; * Store 0x0F in L.
    st over_cnt               ; * Store 0x0F to outer loop counter.
    addi 0x40                 ; * Bump bus value by 0x40 to get 0x4F ('F' in the
    st to_output              ;   terminal's character ROM) and store it
                              ;   into the output buffer.
.over_loop:                   ; * Outer loop; prints lines of various lengths.
    ld over_cnt               ; * Prepare to print as many characters as many
    st print_cnt              ;   iterations we have yet to do.
.print_loop:                  ; * Inner loop; prints individual lines.
    ld to_output | out 1      ; * Load output buffer, print the character in it.
    ld print_cnt              ; * Load loop counter, decrement it, break out of
    dec          | and   | jz ..done  ;   the loop if it got to zero, store
    st print_cnt | jp .print_loop     ;   it back otherwise and iterate.
                                      ; * The 'and' here is a bitwise AND with
                                      ;   L, currently holding 0x0F.
..done:                       ; * End of inner loop.
    ld mf_nofill | out 1      ; * Tell the terminal to not waste time padding
                              ;   new lines with spaces.
    ld to_output | dec        ; * Load output buffer, decrement it,
    st to_output              ;   store it back.
    ld over_cnt               ; * Load outer loop counter, decrement it, break
    dec          | and   | jz .end    ;   out of the loop if it got to zero,
    st over_cnt  | jp .over_loop      ;   store it back otherwise and iterate.
                                      ; * The 'and' here is a bitwise AND with
                                      ;   L, currently holding 0x0F.
.end:                         ; * End of outer loop.
    ld mf_store  | stl        ; * Store "store" command for the terminal into L.
    rng                       ; * Generate a random number, then merge it with
    or           | out 1      ;   the store command and output it. This stores
                              ;   the random number in the terminal's data bus.
    ld mf_colour | out 1 | jp start   ; * Instruct terminal to set the random
                                      ;   number previously stored in its data
                                      ;   bus as the colour for future printing,
                                      ;   then start over.

org_data 0
to_output:
    dw 0
over_cnt:
    dw 7
print_cnt:
    dw 6
zero:
    dw 0
mf_nofill:
    dw 0x2000
mf_store:
    dw 0x8000000
mf_colour:
    dw 0x800
