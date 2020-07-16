_Model "MAPS"                 ; * Specify target model.

%include "common"

; * Inputs.
%define p_keyboard 0x10

; * Outputs.
%define p_display  0x10
%define p_info_out 0x18
%define p_cheater  0x19

; * Memory.
%define m_guess     0x00
%define m_offset    0x01
%define m_score     0x02
%define m_highscore 0x03
%define m_input     0x04

; * Constants.
%define i_max_score          0x05
%define i_too_small          0x02
%define i_correct            0x04
%define i_too_great          0x08
%define i_restart            0x01
%define o_new_game           0x01
%define o_end_of_game        0x02
%define o_highscore          0x04
%define o_enable_in_controls 0x08
%define o_enable_in_reset    0x10
%define o_enable_in_both     0x18

start:
    ld 0                      ; * Zero out
    st [m_highscore]          ;   highscore.

new_game:
    ld o_new_game             ; * Update output to reflect that a
    st [p_info_out]           ;   new game is about to start.
    ld 16                     ; * Guess 16
    st [m_guess]              ;   first.
    ld 8                      ; * Start binary search by halving the 16-number
    st [m_offset]             ;   range, which puts us in the middle.
    ld 0                      ; * Zero out
    st [m_score]              ;   score.
.display:
    ld [m_guess]              ; * Write guess
    st [p_display]            ;   to display.
.get_user_input:
    ld o_enable_in_both       ; * Enable both keyboard
    st [p_info_out]           ;   and reset button.
.check_user_input:
    ld [p_keyboard]           ; * Wait until user
    jz .check_user_input      ;   inputs something.
    st [m_input]              ; * Save user input.
    xor i_too_small           ; * Check if the user claims
    jz guess.too_small        ;   that the guess is too small.
    ld [m_input]              ; * Recall user input.
    xor i_too_great           ; * Check if the user claims
    jz guess.too_great        ;   that the guess is too great.
    ld [m_input]              ; * Recall user input.
    xor i_correct             ; * Check if the user claims
    jz game_over              ;   that the guess is correct.
    ld [m_input]              ; * Recall user input.
    xor i_restart             ; * Check if the user wants to restart.
    jnzg .get_user_input, new_game

guess:
.too_small:
    ld [m_guess]                   ; * Move binary search midpoint to
    add [m_offset]                 ;   the upper half, call cheats if
    jzg game_over.cheater, .next   ;   this causes an overflow.
.too_great:
    ld [m_offset]             ; * Do the same as above but negate
    xor 31                    ;   the offset via 2's complement,
    add 1                     ;   thus subtracting it and moving
    add [m_guess]             ;   the midpoint to the lower half.
.next:
    st [m_guess]              ; * Store midpoint.
    ld [m_score]              ; * Bump score,
    add 1                     ;   save it back
    st [m_score]              ;   for later use.
    ld [m_offset]             ; * Divide the binary search offset
    shr                       ;   by 2 for use in the next round.
    jnz .offset_ok            ; * Check if the next round can actually
    ld [m_score]              ;   happen. If not, it's possible that the
    gt i_max_score            ;   user messed up or is trying to cheat.
    jnz game_over.cheater     ; * Call cheats if the binary search is
    ld 1                      ;   taking too long. Otherwise just fix
.offset_ok:                   ;   the binary search offset? Uh...
    stg [m_offset], new_game.display

game_over:
    ld o_end_of_game          ; * Signal the end of
    st [p_info_out]           ;   the game to the user.
    ld [m_score]              ; * Tell them
    st [p_display]            ;   the score.
    gt [m_highscore]          ; * If they didn' beat their
    jz .wait_for_restart      ;   highscore, just restart.
    ld [m_score]              ; * If they did,
    st [m_highscore]          ;   upgrade highscore
    ld o_highscore            ;   and tell them.
    st [p_info_out]
.wait_for_restart:
    ld o_enable_in_reset      ; * Tell user to reset
    st [p_info_out]           ;   the game.
.check_restart:
    ld [p_keyboard]           ; * Check if the user wants a restart;
    xor i_restart             ;   restart if they do.
    jzg new_game, .check_restart
.cheater:
    ld 0                      ; * Whoop some cheater bum.
    stg [p_cheater], .wait_for_restart
