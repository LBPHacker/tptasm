_Model "I8M7D28S"

%include "common"

start:
    ld loc_4
    addi 0x0F | stl
    st loc_2
    addi 0x40
    st loc_0
.over_loop:
    ld loc_2
    st loc_3
.print_loop:
    ld loc_0  | out 1
    ld loc_3
    dec       | and   | jz ..done
    st loc_3  | jp .print_loop
..done:
    ld loc_1  | out 1
    ld loc_0  | dec
    st loc_0
    ld loc_2
    dec       | and   | jz .end
    st loc_2  | jp .over_loop
.end:
    ld loc_5  | stl
    rng
    or        | out 1
    ld loc_6  | out 1 | jp start

org_data 0
loc_0:
    dw 'G'
loc_1:
    dw 0x2000
loc_2:
    dw 7
loc_3:
    dw 6
loc_4:
    dw 0
loc_5:
    dw 0x8000000
loc_6:
    dw 0x800
