start:
    ldb
    st r0 | ldb
    st r1
    ld r0
loop:
    stl   | ld r1
    xor
    st r0
    ld r1 | setc
    andrl
    st r1
    ld r0 | brc loop 
    out   | br start
