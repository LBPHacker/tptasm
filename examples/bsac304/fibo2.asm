%include "common"

start:
    upd0 A
    add _1
    upd A
    add _1
    upd B
loop:
    add A
    upd A
    add B
    upd B
    jgz loop
    halt
_1:
    data 1
A:
    data 0
B:
    data 0
