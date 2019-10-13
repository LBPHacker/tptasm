_Model "A728D28[0A]"     ; * Specify target model.

start:
    ldb                  ; * Get a number and
    st r0 | ldb          ;   store it in r0, then get another and
    st r1                ;   store that in r1.
    ld r0                ; * Load one of the numbers, this is an entry condition
                         ;   of the loop below.
loop:                    ; * Every time we get here, we have one of the numbers
    stl   | ld r1        ;   loaded. Store it into L, then load the other one.
    xor                  ; * Bitwise XOR the two numbers and store the result
    st r0                ;   into r0, keeping the bits that, were present in one
                         ;   of the two numbers, not both. This effectively sums
                         ;   the non-overlapping portions of the two numbers,
                         ;   yielding a partial sum.
    ld r1 | setc         ; * Load the other number from r1 again (the first one
    andrl                ;   is still in L), bitwise AND them and rotate the
    st r1                ;   result to the left, then store it into r1. This
                         ;   yields the bits that were present in both numbers,
                         ;   but shifted up. This effectively sums the
                         ;   overlapping portions of the two numbers, yielding
                         ;   another partial sum.
                         ; * The sum of these two partial sums is exactly the
                         ;   sum of the two initial numbers. At this point we
                         ;   once again have two numbers that we have to sum,
                         ;   except one of them may be 0. A proof of why this
                         ;   always happens eventually will be provided when
                         ;   I have more time.
    ld r0 | brc loop     ; * Load one of the numbers so the loop can start over.
                         ; * If the bitwise AND has yielded no set bits, the
                         ;   algorithm terminates as the two numbers had no
                         ;   overlapping parts, meaning the sum of their
                         ;   non-overlapping parts is exactly their sum.
    out   | br start     ; * Output sum and start over.
