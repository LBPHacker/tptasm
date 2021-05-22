_Model "MICRO21"         ; * Specify target model.

%include "common"        ; * Common header built into the assembler.

start:
    nin a                ; * Input demo index.
    test a, 6            ; * If the index
    ifa                  ;   is above 6,
    stop                 ;   stop.
    add a, .jump_table   ; * Otherwise, calculate offset into the jump table
    jmp a                ;   with the index and jump to it.
.jump_table:
    stopv                ; * Index 0: stop.
    jmp demo_guess       ; * Index 1: guess the number demo.
    jmp demo_fibonacci   ; * Index 2: Fibonacci demo.
    jmp demo_addition    ; * Index 3: simple addition demo.
    jmp demo_odds        ; * Index 4: odd counter demo.
    stop                 ; * Index 5: stop.
    sysr                 ; * Index 6: reset system, though this index and also
    stopv                ;   everything after it is inaccessible due to the
                         ;   index >= 6 check earlier.



org 0x2A                 ; * The actual demos are aligned so that they end
                         ;   exactly at the end of the ROM.
                         ; * I'd thought that this had been done for aesthetic
                         ;   reasons, but by RockerM4NHUN's account the reason
                         ;   is just that it makes changing existing code
                         ;   easier. Yeah, I guess having an assembler helps.



    nopv
    stop
demo_addition:           ; * It doesn't get any simpler than this. Two numbers
    nin a                ;   are entered and their sum is printed back out.
    nin b                ; * Result is truncated to 8 bits; this could be worked
    add a, b             ;   around by moving 0 to b and adc-ing 0 to it, then
    out a                ;   doing out a, b instead of out a. But even if this
    stop                 ;   were to be done, the decimal display would truncate
                         ;   the output to 3 digits.



%define m_buf_pointer 0x7F
%define m_odd_counter 0x7E
    nopv
    stop
demo_odds:               ; * Odd counter demo. Counts odd numbers in input,
                         ;   which consists of all the integers entered by the
                         ;   user until the first zero.
                         ; * It first outputs the amount of integers entered,
                         ;   then the amount of odd integers among those.
    sysr                 ; * Reset system, storing 0 in m_buf_pointer,
                         ;   m_odd_counter and register b, among other things.
                         ; * b now points to 0 and will be used as a pointer
                         ;   into the buffer to which the numbers being entered
                         ;   are saved.
.get_number:
    nin a                ; * Get a number.
    ifz a                ; * If it's zero,
    jmp ..done           ;   stop asking for numbers.
    sto a, b             ; * Store a to wherever b points,
    add b, 1             ;   then bump b.
    jmp .get_number      ; * Go again.
..done:
    out b                ; * Since the buffer starts at 0, b, which points just
                         ;   beyond its end, consequently also holds the amount
                         ;   of numbers in the buffer. Print that.
.count_odds:
    ifz b                ; * If there are no more numbers left,
    jmp ..done           ;   stop.
    add b, 255           ; * Subtract one from the pointer so it points to a
                         ;   number that hasn't been processed yet.
    lod a, b             ; * Load that number into a.
    sto b, m_buf_pointer ; * Save pointer.
    lod b, m_odd_counter ; * Recall odd counter,
    if a, 1              ;   increment it if the number
    add b, 1             ;   being processed is odd,
    sto b, m_odd_counter ;   then save it back again.
    lod b, m_buf_pointer ; * Recall pointer.
    jmp .count_odds
..done:
    lod a, m_odd_counter ; * Recall odd counter
    out a                ;   and print it.
    stop



    nopv
    stop
demo_guess:              ; * Guess the number demo. Let the user think of a
                         ;   number between 0 and 255 inclusive and find it in
                         ;   at most eight guesses with a simple binary search.
                         ; * The demo can even tell if the user is being evil.
    sysr                 ; * Reset everything.
    copy a, 0x80         ; * a = 0x80
    copy b, a            ; * b = 0x80
    jmp .skip_halving    ; * Try 0x80 first, skip the first halving cycle.
.smaller_range:
    shr a, 1             ; * Halve guessing range.
    ifz a                ; * If this makes the guessing range zero,
    jmp .final_guess     ;   stop guessing.
    or b, a              ; * Merge guessing range into temporary guess.
.skip_halving:
    out b                ; * Display guess.
    lin                  ; * If the user tells us that the number they thought
    jly .guessed_it      ;   of is equal to b, we're done.
    lin                  ; * If the user tells us that the number they thought
    ifly                 ;   of is smaller than b, undo the merging of the
    xor b, a             ;   guessing range, ruling out the upper half.
    jmp .smaller_range   ; * Then unconditionally try again with a smaller
                         ;   range to rule out another half.
.final_guess:            ; * So we stopped guessing.
    out b                ; * Print final guess, which we know to be right due
    lin                  ;   to having executed a perfect binary search.
    ifln                 ; * If the user doesn't agree, print 666. Note that
    out 0x9A             ;   out gets 0x9A in both of its operands here, and it
                         ;   sends the 10 LSB of second:first to the display.
                         ;   0x9A9A & 0x3FF = 666. The user is evil.
    ifly                 ; * If the user agrees, we really did guess the
.guessed_it:             ;   number they thought of.
    out 0                ; * We're done, clear display.
    stop



    nopv
    stop
demo_fibonacci:          ; * Fibonacci demo. 1 is displayed twice, then a
                         ;   few more terms of the sequence up to 233.
    sysr                 ; * This resets a and b to 0, among other things.
    copy a, 1            ; * a = 1, b = 0; classic starting condition.
    nop                  ; * I'm not exactly sure why these nops are here; the
.loop:                   ;   documentation says you only need nops between two
    nop                  ;   out instructions if there's no jump between them.
    out a                ; * Output next term.
    add b, a             ; * b += a, b now contains the next term of the
    jc .overflow         ;   sequence. Stop if the addition overflows.
    out b                ; * Output next term.
    add a, b             ; * a += b, a now contains the next term of the
    jnc .loop            ;   sequence. Stop if the addition overflows.
.overflow:               ; * So basically a and b leapfrog each other.
    out 0                ; * Display 0 to mark the end of the sequence and stop.
    stop



%define m_stack_ptr 0x7F
%define m_subr_addr 0x7E
    nopv                 ; * Code that implements subroutine call and return
    stop                 ;   functionality (which RockerM4NHUN seems to have
subroutine:              ;   forgotten to tell anyone about :P).
                         ; * As far as I can tell, none of the demos use this
                         ;   code and it's not reachable from the demo selector
                         ;   either (i.e. it's dead code).
                         ; * The call stack pointer is stored at 0x7F and
                         ;   the stack grows upwards. 0x7E is used for
                         ;   temporarily saving the subroutine address in .call.
.return:
    lod a, m_stack_ptr   ; * Load call stack pointer,
    add a, 255           ;   decrement it so it points to the return address,
    sto a, m_stack_ptr   ;   save the decremented version back.
    lod a, a             ; * Load return address
    jmp a                ;   and jump to it.
.call:
    sto a, m_subr_addr   ; * Back up a; this is the address of the subroutine
                         ;   being called. Register b holds the return address,
                         ;   so there should probably be a stip b at the call
                         ;   site. No guarantees though, never tried stip.
    lod a, m_stack_ptr   ; * Load call stack pointer,
    sto b, a             ;   store return address to the top of the stack,
    add a, 1             ;   increment call stack pointer,
    sto a, m_stack_ptr   ;   save the incremented version back.
    lod a, m_subr_addr   ; * Recall the subroutine address
    jmp a                ;   and jump to it.

