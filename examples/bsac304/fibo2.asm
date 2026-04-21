%include "common"

start:
    T var_x
    A const_1
    U var_x
    A const_1
    U var_y
loop:
    A var_x
    U var_x
    A var_y
    U var_y
    E loop
    Z
const_1:
    data 1
var_x:
    data 0
var_y:
    data 0
