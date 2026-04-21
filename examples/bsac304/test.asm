%include "common"

start:
    T var_x
    A const_1
    U var_x
    J error; acc should be +1
    G error; acc should be +1
    T var_x
    E error; acc should be 0
    G error; acc should be 0
    S const_2
    J error; acc should be -2
    E error; acc should be -2
    X
    X
    T var_x;
    U var_x; x = 0
    A nreps
loop:
; acc should be the updated 'nreps' here
    T nreps
    A var_x
    A const_1
    U var_x
    A var_x; compute y = 2x
    T var_y
    A nreps
    S const_1
    E loop
    Z


error:
    T var_x
    A const_EEEE
    Z

const_1:
    data 1
const_2:
    data 2
const_EEEE:
    data 0xEEEE
nreps:
    data 10
var_x:
    data 0
var_y:
    data 0
