	; IntyBASIC compiler v1.4.2 Jun/01/2020
	;
	; Prologue for IntyBASIC programs
	; by Oscar Toledo G.  http://nanochess.org/
	;
	; Revision: Jan/30/2014. Spacing adjustment and more comments.
	; Revision: Apr/01/2014. It now sets the starting screen pos. for PRINT
	; Revision: Aug/26/2014. Added PAL detection code.
	; Revision: Dec/12/2014. Added optimized constant multiplication routines.
	;                        by James Pujals.
	; Revision: Jan/25/2015. Added marker for automatic title replacement.
	;                        (option --title of IntyBASIC)
	; Revision: Aug/06/2015. Turns off ECS sound. Seed random generator using
	;                        trash in 16-bit RAM. Solved bugs and optimized
	;                        macro for constant multiplication.
	; Revision: Jan/12/2016. Solved bug in PAL detection.
	; Revision: May/03/2016. Changed in _mode_select initialization.
	; Revision: Jul/31/2016. Solved bug in multiplication by 126 and 127.
	; Revision: Sep/08/2016. Now CLRSCR initializes screen position for PRINT,
	;                        this solves bug when user programs goes directly
	;                        to PRINT.
	; Revision: Oct/21/2016. Accelerated MEMSET.
	; Revision: Jan/09/2018. Adjusted PAL/NTSC constant.
	; Revision: Feb/05/2018. Forces initialization of Intellivoice if included.
	;                        So VOICE INIT ceases to be dangerous.
	; Revision: Oct/30/2018. Redesigned PAL/NTSC detection using intvnut code,
	;                        also now compatible with Tutorvision. Reformatted.
	; Revision: Jan/10/2018. Added ECS detection.
	;

	ROMW 16
	ORG $5000

	; This macro will 'eat' SRCFILE directives if the assembler doesn't support the directive.
	IF ( DEFINED __FEATURE.SRCFILE ) = 0
	    MACRO SRCFILE x, y
	    ; macro must be non-empty, but a comment works fine.
	    ENDM
	ENDI

	;
	; ROM header
	;
	BIDECLE _ZERO		; MOB picture base
	BIDECLE _ZERO		; Process table
	BIDECLE _MAIN		; Program start
	BIDECLE _ZERO		; Background base image
	BIDECLE _ONES		; GRAM
	BIDECLE _TITLE		; Cartridge title and date
	DECLE   $03C0		; No ECS title, jump to code after title,
				; ... no clicks
                                
_ZERO:	DECLE   $0000		; Border control
	DECLE   $0000		; 0 = color stack, 1 = f/b mode
        
_ONES:	DECLE   $0001, $0001	; Initial color stack 0 and 1: Blue
	DECLE   $0001, $0001	; Initial color stack 2 and 3: Blue
	DECLE   $0001		; Initial border color: Blue

CLRSCR:	MVII #$200,R4		; Used also for CLS
	MVO R4,_screen		; Set up starting screen position for PRINT
	MVII #$F0,R1
FILLZERO:
	CLRR R0
MEMSET:
	SARC R1,2
	BNOV $+4
	MVO@ R0,R4
	MVO@ R0,R4
	BNC $+3
	MVO@ R0,R4
	BEQ $+7
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	DECR R1
	BNE $-5
	JR R5

	;
	; Title, Intellivision EXEC will jump over it and start
	; execution directly in _MAIN
	;
	; Note mark is for automatic replacement by IntyBASIC
_TITLE:
	BYTE 125,'Maze',0
        
	;
	; Main program
	;
_MAIN:
	DIS			; Disable interrupts
	MVII #STACK,R6

	;
	; Clean memory
	;
	CALL CLRSCR		; Clean up screen, right here to avoid brief
				; screen display of title in Sears Intellivision.
	MVII #$00e,R1		; 14 of sound (ECS)
	MVII #$0f0,R4		; ECS PSG
	CALL FILLZERO
	MVII #$0fe,R1		; 240 words of 8 bits plus 14 of sound
	MVII #$100,R4		; 8-bit scratch RAM
	CALL FILLZERO

	; Seed random generator using 16 bit RAM (not cleared by EXEC)
	CLRR R0
	MVII #$02F0,R4
	MVII #$0110/4,R1	; Includes phantom memory for extra randomness
_MAIN4:				; This loop is courtesy of GroovyBee
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	DECR R1
	BNE _MAIN4
	MVO R0,_rand

	MVII #$058,R1		; 88 words of 16 bits
	MVII #$308,R4		; 16-bit scratch RAM
	CALL FILLZERO

	; PAL/NTSC detect
	CALL _set_isr
	DECLE _pal1
	EIS
	DECR PC			; This is a kind of HALT instruction

	; First interrupt may come at a weird time on Tutorvision, or
	; if other startup timing changes.
_pal1:	SUBI #8,R6		; Drop interrupt stack.
	CALL _set_isr
	DECLE _pal2
	DECR PC

	; Second interrupt is safe for initializing MOBs.
	; We will know the screen is off after this one fires.
_pal2:	SUBI #8,R6		; Drop interrupt stack.
	CALL _set_isr
	DECLE _pal3
	; clear MOBs
	CLRR R0
	CLRR R4
	MVII #$18,R2
_pal2_lp:
	MVO@ R0,R4
	DECR R2
	BNE _pal2_lp
	MVO R0,$30		; Reset horizontal delay register
	MVO R0,$31		; Reset vertical delay register

	MVII #-1100,R2		; PAL/NTSC threshold
_pal2_cnt:
	INCR R2
	B _pal2_cnt

	; The final count in R2 will either be negative or positive.
	; If R2 is still -ve, NTSC; else PAL.
_pal3:	SUBI #8,R6		; Drop interrupt stack.
	RLC R2,1
	RLC R2,1
	ANDI #1,R2		; 1 = NTSC, 0 = PAL

	MVII #$55,R1
	MVO R1,$4040
	MVII #$AA,R1
	MVO R1,$4041
	MVI $4040,R1
	CMPI #$55,R1
	BNE _ecs1
	MVI $4041,R1
	CMPI #$AA,R1
	BNE _ecs1
	ADDI #2,R2		; ECS detected flag
_ecs1:
	MVO R2,_ntsc

	CALL _set_isr
	DECLE _int_vector

	CALL CLRSCR		; Because _screen was reset to zero
	CALL _wait
	CALL _init_music
	MVII #2,R0		; Color Stack mode
	MVO R0,_mode_select
	MVII #$038,R0
	MVO R0,$01F8		; Configures sound
	MVO R0,$00F8		; Configures sound (ECS)
	CALL IV_INIT_and_wait	; Setup Intellivoice

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- James Pujals (DZ-Jay), 2014                              *;
;* ======================================================================== *;

; Modified by Oscar Toledo G. (nanochess), Aug/06/2015
; * Tested all multiplications with automated test.
; * Accelerated multiplication by 7,14,15,28,31,60,62,63,112,120,124
; * Solved bug in multiplication by 23,39,46,47,55,71,78,79,87,92,93,94,95,103,110,111,119
; * Improved sequence of instructions to be more interruptible.

;; ======================================================================== ;;
;;  MULT reg, tmp, const                                                    ;;
;;  Multiplies "reg" by constant "const" and using "tmp" for temporary      ;;
;;  calculations.  The result is placed in "reg."  The multiplication is    ;;
;;  performed by an optimal combination of shifts, additions, and           ;;
;;  subtractions.                                                           ;;
;;                                                                          ;;
;;  NOTE:   The resulting contents of the "tmp" are undefined.              ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      reg         A register containing the multiplicand.                 ;;
;;      tmp         A register for temporary calculations.                  ;;
;;      const       The constant multiplier.                                ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      reg         Output value.                                           ;;
;;      tmp         Trashed.                                                ;;
;;      .ERR.Failed True if operation failed.                               ;;
;; ======================================================================== ;;
MACRO   MULT reg, tmp, const
;
    LISTING "code"

_mul.const      QSET    %const%
_mul.done       QSET    0

        IF (%const% > $7F)
_mul.const      QSET    (_mul.const SHR 1)
                SLL     %reg%,  1
        ENDI

        ; Multiply by $00 (0)
        IF (_mul.const = $00)
_mul.done       QSET    -1
                CLRR    %reg%
        ENDI

        ; Multiply by $01 (1)
        IF (_mul.const = $01)
_mul.done       QSET    -1
                ; Nothing to do
        ENDI

        ; Multiply by $02 (2)
        IF (_mul.const = $02)
_mul.done       QSET    -1
                SLL     %reg%,  1
        ENDI

        ; Multiply by $03 (3)
        IF (_mul.const = $03)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $04 (4)
        IF (_mul.const = $04)
_mul.done       QSET    -1
                SLL     %reg%,  2
        ENDI

        ; Multiply by $05 (5)
        IF (_mul.const = $05)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $06 (6)
        IF (_mul.const = $06)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $07 (7)
        IF (_mul.const = $07)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $08 (8)
        IF (_mul.const = $08)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
        ENDI

        ; Multiply by $09 (9)
        IF (_mul.const = $09)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0A (10)
        IF (_mul.const = $0A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0B (11)
        IF (_mul.const = $0B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0C (12)
        IF (_mul.const = $0C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0D (13)
        IF (_mul.const = $0D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0E (14)
        IF (_mul.const = $0E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0F (15)
        IF (_mul.const = $0F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $10 (16)
        IF (_mul.const = $10)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $11 (17)
        IF (_mul.const = $11)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $12 (18)
        IF (_mul.const = $12)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $13 (19)
        IF (_mul.const = $13)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $14 (20)
        IF (_mul.const = $14)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $15 (21)
        IF (_mul.const = $15)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $16 (22)
        IF (_mul.const = $16)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $17 (23)
        IF (_mul.const = $17)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $18 (24)
        IF (_mul.const = $18)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $19 (25)
        IF (_mul.const = $19)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1A (26)
        IF (_mul.const = $1A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1B (27)
        IF (_mul.const = $1B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1C (28)
        IF (_mul.const = $1C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1D (29)
        IF (_mul.const = $1D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1E (30)
        IF (_mul.const = $1E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1F (31)
        IF (_mul.const = $1F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $20 (32)
        IF (_mul.const = $20)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
        ENDI

        ; Multiply by $21 (33)
        IF (_mul.const = $21)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $22 (34)
        IF (_mul.const = $22)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $23 (35)
        IF (_mul.const = $23)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $24 (36)
        IF (_mul.const = $24)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $25 (37)
        IF (_mul.const = $25)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $26 (38)
        IF (_mul.const = $26)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $27 (39)
        IF (_mul.const = $27)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $28 (40)
        IF (_mul.const = $28)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $29 (41)
        IF (_mul.const = $29)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2A (42)
        IF (_mul.const = $2A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2B (43)
        IF (_mul.const = $2B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2C (44)
        IF (_mul.const = $2C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2D (45)
        IF (_mul.const = $2D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2E (46)
        IF (_mul.const = $2E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $2F (47)
        IF (_mul.const = $2F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $30 (48)
        IF (_mul.const = $30)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $31 (49)
        IF (_mul.const = $31)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $32 (50)
        IF (_mul.const = $32)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $33 (51)
        IF (_mul.const = $33)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $34 (52)
        IF (_mul.const = $34)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $35 (53)
        IF (_mul.const = $35)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $36 (54)
        IF (_mul.const = $36)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $37 (55)
        IF (_mul.const = $37)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
		SLL	%reg%,	1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $38 (56)
        IF (_mul.const = $38)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $39 (57)
        IF (_mul.const = $39)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3A (58)
        IF (_mul.const = $3A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3B (59)
        IF (_mul.const = $3B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3C (60)
        IF (_mul.const = $3C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3D (61)
        IF (_mul.const = $3D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3E (62)
        IF (_mul.const = $3E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3F (63)
        IF (_mul.const = $3F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $40 (64)
        IF (_mul.const = $40)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $41 (65)
        IF (_mul.const = $41)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $42 (66)
        IF (_mul.const = $42)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $43 (67)
        IF (_mul.const = $43)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $44 (68)
        IF (_mul.const = $44)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $45 (69)
        IF (_mul.const = $45)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $46 (70)
        IF (_mul.const = $46)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $47 (71)
        IF (_mul.const = $47)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $48 (72)
        IF (_mul.const = $48)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $49 (73)
        IF (_mul.const = $49)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4A (74)
        IF (_mul.const = $4A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4B (75)
        IF (_mul.const = $4B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4C (76)
        IF (_mul.const = $4C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4D (77)
        IF (_mul.const = $4D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4E (78)
        IF (_mul.const = $4E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $4F (79)
        IF (_mul.const = $4F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $50 (80)
        IF (_mul.const = $50)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $51 (81)
        IF (_mul.const = $51)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $52 (82)
        IF (_mul.const = $52)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $53 (83)
        IF (_mul.const = $53)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $54 (84)
        IF (_mul.const = $54)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $55 (85)
        IF (_mul.const = $55)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $56 (86)
        IF (_mul.const = $56)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $57 (87)
        IF (_mul.const = $57)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR    %reg%,	%tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $58 (88)
        IF (_mul.const = $58)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $59 (89)
        IF (_mul.const = $59)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5A (90)
        IF (_mul.const = $5A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5B (91)
        IF (_mul.const = $5B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5C (92)
        IF (_mul.const = $5C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5D (93)
        IF (_mul.const = $5D)
_mul.done       QSET    -1
		MOVR	%reg%,	%tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5E (94)
        IF (_mul.const = $5E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5F (95)
        IF (_mul.const = $5F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                ADDR	%reg%,	%reg%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $60 (96)
        IF (_mul.const = $60)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $61 (97)
        IF (_mul.const = $61)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $62 (98)
        IF (_mul.const = $62)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $63 (99)
        IF (_mul.const = $63)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $64 (100)
        IF (_mul.const = $64)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $65 (101)
        IF (_mul.const = $65)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $66 (102)
        IF (_mul.const = $66)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $67 (103)
        IF (_mul.const = $67)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $68 (104)
        IF (_mul.const = $68)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $69 (105)
        IF (_mul.const = $69)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6A (106)
        IF (_mul.const = $6A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6B (107)
        IF (_mul.const = $6B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6C (108)
        IF (_mul.const = $6C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6D (109)
        IF (_mul.const = $6D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6E (110)
        IF (_mul.const = $6E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $6F (111)
        IF (_mul.const = $6F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $70 (112)
        IF (_mul.const = $70)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $71 (113)
        IF (_mul.const = $71)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $72 (114)
        IF (_mul.const = $72)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $73 (115)
        IF (_mul.const = $73)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $74 (116)
        IF (_mul.const = $74)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $75 (117)
        IF (_mul.const = $75)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $76 (118)
        IF (_mul.const = $76)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $77 (119)
        IF (_mul.const = $77)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $78 (120)
        IF (_mul.const = $78)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $79 (121)
        IF (_mul.const = $79)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7A (122)
        IF (_mul.const = $7A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7B (123)
        IF (_mul.const = $7B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7C (124)
        IF (_mul.const = $7C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7D (125)
        IF (_mul.const = $7D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7E (126)
        IF (_mul.const = $7E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7F (127)
        IF (_mul.const = $7F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        IF  (_mul.done = 0)
            ERR $("Invalid multiplication constant \'%const%\', must be between 0 and ", $#($7F), ".")
        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  EOF: pm:mac:lang:mult                                                   ;;
;; ======================================================================== ;;

	;FILE Maze.bas
	;[1] 	REM
	SRCFILE "Maze.bas",1
	;[2] 	REM Maze
	SRCFILE "Maze.bas",2
	;[3] 	REM CIS 272 Honors Project
	SRCFILE "Maze.bas",3
	;[4] 	REM by Tej Sai Kakumanu
	SRCFILE "Maze.bas",4
	;[5] 	REM Dec 2nd 2024
	SRCFILE "Maze.bas",5
	;[6] 	REM
	SRCFILE "Maze.bas",6
	;[7] 
	SRCFILE "Maze.bas",7
	;[8] 	REM Include useful predefined constants
	SRCFILE "Maze.bas",8
	;[9] 	INCLUDE "constants.bas"
	SRCFILE "Maze.bas",9
	;FILE /Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas
	;[1] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",1
	;[2] REM HEADER - CONSTANTS.BAS
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",2
	;[3] REM
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",3
	;[4] REM Started by Mark Ball, July 2015
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",4
	;[5] REM
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",5
	;[6] REM Constants for use in IntyBASIC
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",6
	;[7] REM
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",7
	;[8] REM HISTORY
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",8
	;[9] REM -------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",9
	;[10] REM 1.00F 05/07/15 - First version.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",10
	;[11] REM 1.01F 07/07/15 - Added disc directions.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",11
	;[12] REM                - Added background modes.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",12
	;[13] REM                - Minor comment changes.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",13
	;[14] REM 1.02F 08/07/15 - Renamed constants.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",14
	;[15] REM                - Added background access information.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",15
	;[16] REM                - Adjustments to layout.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",16
	;[17] REM 1.03F 08/07/15 - Fixed comment delimiter.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",17
	;[18] REM 1.04F 11/07/15 - Added useful functions.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",18
	;[19] REM                - Added controller movement mask.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",19
	;[20] REM 1.05F 11/07/15 - Added BACKGROUND constants.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",20
	;[21] REM 1.06F 11/07/15 - Changed Y, X order to X, Y in DEF FN functions.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",21
	;[22] REM 1.07F 11/07/15 - Added colour stack advance.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",22
	;[23] REM 1.08F 12/07/15 - Added functions for sprite position handling.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",23
	;[24] REM 1.09F 12/07/15 - Added a function for resetting a sprite.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",24
	;[25] REM 1.10F 13/07/15 - Added keypad constants.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",25
	;[26] REM 1.11F 13/07/15 - Added side button constants.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",26
	;[27] REM 1.12F 13/07/15 - Updated sprite functions.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",27
	;[28] REM 1.13F 19/07/15 - Added border masking constants.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",28
	;[29] REM 1.14F 20/07/15 - Added a combined border masking constant.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",29
	;[30] REM 1.15F 20/07/15 - Renamed border masking constants to BORDER_HIDE_xxxx.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",30
	;[31] REM 1.16F 28/09/15 - Fixed disc direction typos.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",31
	;[32] REM 1.17F 30/09/15 - Fixed DISC_SOUTH_WEST value.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",32
	;[33] REM 1.18F 05/12/15 - Fixed BG_XXXX colours.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",33
	;[34] REM 1.19F 01/01/16 - Changed name of BACKTAB constant to avoid confusion with #BACKTAB array.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",34
	;[35] REM                - Added pause key constants.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",35
	;[36] REM 1.20F 14/01/16 - Added coloured squares mode's pixel colours.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",36
	;[37] REM 1.21F 15/01/16 - Added coloured squares mode's X and Y limits.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",37
	;[38] REM 1.22F 23/01/16 - Added PSG constants.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",38
	;[39] REM 1.23F 24/01/16 - Fixed typo in PSG comments.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",39
	;[40] REM 1.24F 16/11/16 - Added toggle DEF FN's for sprite's BEHIND, HIT and VISIBLE.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",40
	;[41] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",41
	;[42] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",42
	;[43] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",43
	;[44] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",44
	;[45] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",45
	;[46] REM Background information.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",46
	;[47] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",47
	;[48] CONST BACKTAB_ADDR			= $0200		' Start of the BACKground TABle (BACKTAB) in RAM.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",48
	;[49] CONST BACKGROUND_ROWS			= 12		' Height of the background in cards.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",49
	;[50] CONST BACKGROUND_COLUMNS		= 20		' Width of the background in cards.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",50
	;[51] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",51
	;[52] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",52
	;[53] REM Background GRAM cards.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",53
	;[54] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",54
	;[55] CONST BG00 				= $0800
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",55
	;[56] CONST BG01 				= $0808
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",56
	;[57] CONST BG02 				= $0810
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",57
	;[58] CONST BG03 				= $0818
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",58
	;[59] CONST BG04 				= $0820
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",59
	;[60] CONST BG05 				= $0828
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",60
	;[61] CONST BG06 				= $0830
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",61
	;[62] CONST BG07 				= $0838
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",62
	;[63] CONST BG08 				= $0840
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",63
	;[64] CONST BG09 				= $0848
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",64
	;[65] CONST BG10 				= $0850
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",65
	;[66] CONST BG11 				= $0858
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",66
	;[67] CONST BG12 				= $0860
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",67
	;[68] CONST BG13 				= $0868
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",68
	;[69] CONST BG14 				= $0870
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",69
	;[70] CONST BG15 				= $0878
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",70
	;[71] CONST BG16 				= $0880
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",71
	;[72] CONST BG17 				= $0888
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",72
	;[73] CONST BG18 				= $0890
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",73
	;[74] CONST BG19 				= $0898
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",74
	;[75] CONST BG20 				= $08A0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",75
	;[76] CONST BG21 				= $08A8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",76
	;[77] CONST BG22 				= $08B0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",77
	;[78] CONST BG23 				= $08B8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",78
	;[79] CONST BG24 				= $08C0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",79
	;[80] CONST BG25 				= $08C8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",80
	;[81] CONST BG26 				= $08D0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",81
	;[82] CONST BG27 				= $08D8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",82
	;[83] CONST BG28 				= $08E0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",83
	;[84] CONST BG29 				= $08E8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",84
	;[85] CONST BG30 				= $08F0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",85
	;[86] CONST BG31 				= $08F8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",86
	;[87] CONST BG32 				= $0900
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",87
	;[88] CONST BG33 				= $0908
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",88
	;[89] CONST BG34 				= $0910
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",89
	;[90] CONST BG35 				= $0918
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",90
	;[91] CONST BG36 				= $0920
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",91
	;[92] CONST BG37 				= $0928
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",92
	;[93] CONST BG38 				= $0930
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",93
	;[94] CONST BG39 				= $0938
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",94
	;[95] CONST BG40 				= $0940
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",95
	;[96] CONST BG41 				= $0948
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",96
	;[97] CONST BG42 				= $0950
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",97
	;[98] CONST BG43 				= $0958
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",98
	;[99] CONST BG44 				= $0960
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",99
	;[100] CONST BG45 				= $0968
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",100
	;[101] CONST BG46 				= $0970
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",101
	;[102] CONST BG47 				= $0978
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",102
	;[103] CONST BG48 				= $0980
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",103
	;[104] CONST BG49 				= $0988
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",104
	;[105] CONST BG50 				= $0990
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",105
	;[106] CONST BG51 				= $0998
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",106
	;[107] CONST BG52 				= $09A0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",107
	;[108] CONST BG53 				= $09A8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",108
	;[109] CONST BG54 				= $09B0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",109
	;[110] CONST BG55 				= $09B8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",110
	;[111] CONST BG56 				= $09C0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",111
	;[112] CONST BG57 				= $09C8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",112
	;[113] CONST BG58 				= $09D0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",113
	;[114] CONST BG59 				= $09D8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",114
	;[115] CONST BG60 				= $09E0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",115
	;[116] CONST BG61 				= $09E8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",116
	;[117] CONST BG62 				= $09F0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",117
	;[118] CONST BG63 				= $09F8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",118
	;[119] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",119
	;[120] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",120
	;[121] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",121
	;[122] REM GRAM card index numbers.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",122
	;[123] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",123
	;[124] REM Note: For use with the "define" command.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",124
	;[125] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",125
	;[126] CONST DEF00 				= $0000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",126
	;[127] CONST DEF01 				= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",127
	;[128] CONST DEF02 				= $0002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",128
	;[129] CONST DEF03 				= $0003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",129
	;[130] CONST DEF04 				= $0004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",130
	;[131] CONST DEF05 				= $0005
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",131
	;[132] CONST DEF06 				= $0006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",132
	;[133] CONST DEF07 				= $0007
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",133
	;[134] CONST DEF08 				= $0008
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",134
	;[135] CONST DEF09 				= $0009
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",135
	;[136] CONST DEF10 				= $000A
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",136
	;[137] CONST DEF11 				= $000B
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",137
	;[138] CONST DEF12 				= $000C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",138
	;[139] CONST DEF13 				= $000D
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",139
	;[140] CONST DEF14 				= $000E
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",140
	;[141] CONST DEF15 				= $000F
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",141
	;[142] CONST DEF16 				= $0010
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",142
	;[143] CONST DEF17 				= $0011
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",143
	;[144] CONST DEF18 				= $0012
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",144
	;[145] CONST DEF19 				= $0013
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",145
	;[146] CONST DEF20 				= $0014
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",146
	;[147] CONST DEF21 				= $0015
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",147
	;[148] CONST DEF22 				= $0016
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",148
	;[149] CONST DEF23 				= $0017
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",149
	;[150] CONST DEF24 				= $0018
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",150
	;[151] CONST DEF25 				= $0019
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",151
	;[152] CONST DEF26 				= $001A
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",152
	;[153] CONST DEF27 				= $001B
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",153
	;[154] CONST DEF28 				= $001C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",154
	;[155] CONST DEF29 				= $001D
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",155
	;[156] CONST DEF30 				= $001E
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",156
	;[157] CONST DEF31 				= $001F
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",157
	;[158] CONST DEF32 				= $0020
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",158
	;[159] CONST DEF33 				= $0021
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",159
	;[160] CONST DEF34 				= $0022
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",160
	;[161] CONST DEF35 				= $0023
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",161
	;[162] CONST DEF36 				= $0024
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",162
	;[163] CONST DEF37 				= $0025
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",163
	;[164] CONST DEF38 				= $0026
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",164
	;[165] CONST DEF39 				= $0027
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",165
	;[166] CONST DEF40 				= $0028
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",166
	;[167] CONST DEF41 				= $0029
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",167
	;[168] CONST DEF42 				= $002A
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",168
	;[169] CONST DEF43 				= $002B
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",169
	;[170] CONST DEF44 				= $002C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",170
	;[171] CONST DEF45 				= $002D
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",171
	;[172] CONST DEF46 				= $002E
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",172
	;[173] CONST DEF47 				= $002F
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",173
	;[174] CONST DEF48 				= $0030
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",174
	;[175] CONST DEF49 				= $0031
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",175
	;[176] CONST DEF50 				= $0032
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",176
	;[177] CONST DEF51 				= $0033
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",177
	;[178] CONST DEF52 				= $0034
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",178
	;[179] CONST DEF53 				= $0035
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",179
	;[180] CONST DEF54 				= $0036
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",180
	;[181] CONST DEF55 				= $0037
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",181
	;[182] CONST DEF56 				= $0038
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",182
	;[183] CONST DEF57 				= $0039
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",183
	;[184] CONST DEF58 				= $003A
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",184
	;[185] CONST DEF59 				= $003B
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",185
	;[186] CONST DEF60 				= $003C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",186
	;[187] CONST DEF61 				= $003D
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",187
	;[188] CONST DEF62 				= $003E
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",188
	;[189] CONST DEF63 				= $003F
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",189
	;[190] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",190
	;[191] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",191
	;[192] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",192
	;[193] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",193
	;[194] REM Screen modes.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",194
	;[195] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",195
	;[196] REM Note: For use with the "mode" command.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",196
	;[197] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",197
	;[198] CONST SCREEN_COLOR_STACK		= $0000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",198
	;[199] CONST SCREEN_FOREGROUND_BACKGROUND	= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",199
	;[200] REM Abbreviated versions.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",200
	;[201] CONST SCREEN_CS				= $0000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",201
	;[202] CONST SCREEN_FB				= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",202
	;[203] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",203
	;[204] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",204
	;[205] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",205
	;[206] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",206
	;[207] REM COLORS - Border.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",207
	;[208] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",208
	;[209] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",209
	;[210] REM - For use with the commands "mode 0" and "mode 1".
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",210
	;[211] REM - For use with the "border" command.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",211
	;[212] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",212
	;[213] CONST BORDER_BLACK			= $0000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",213
	;[214] CONST BORDER_BLUE			= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",214
	;[215] CONST BORDER_RED			= $0002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",215
	;[216] CONST BORDER_TAN			= $0003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",216
	;[217] CONST BORDER_DARKGREEN			= $0004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",217
	;[218] CONST BORDER_GREEN			= $0005
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",218
	;[219] CONST BORDER_YELLOW			= $0006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",219
	;[220] CONST BORDER_WHITE			= $0007
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",220
	;[221] CONST BORDER_GREY			= $0008
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",221
	;[222] CONST BORDER_CYAN			= $0009
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",222
	;[223] CONST BORDER_ORANGE			= $000A
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",223
	;[224] CONST BORDER_BROWN			= $000B
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",224
	;[225] CONST BORDER_PINK			= $000C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",225
	;[226] CONST BORDER_LIGHTBLUE			= $000D
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",226
	;[227] CONST BORDER_YELLOWGREEN		= $000E
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",227
	;[228] CONST BORDER_PURPLE			= $000F
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",228
	;[229] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",229
	;[230] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",230
	;[231] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",231
	;[232] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",232
	;[233] REM BORDER - Edge masks.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",233
	;[234] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",234
	;[235] REM Note: For use with the "border color, edge" command.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",235
	;[236] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",236
	;[237] CONST BORDER_HIDE_LEFT_EDGE		= $0001		' Hide the leftmost column of the background.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",237
	;[238] CONST BORDER_HIDE_TOP_EDGE		= $0002		' Hide the topmost row of the background.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",238
	;[239] CONST BORDER_HIDE_TOP_LEFT_EDGE		= $0003		' Hide both the topmost row and leftmost column of the background.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",239
	;[240] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",240
	;[241] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",241
	;[242] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",242
	;[243] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",243
	;[244] REM COLORS - Mode 0 (Color Stack).
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",244
	;[245] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",245
	;[246] REM Stack
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",246
	;[247] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",247
	;[248] REM Note: For use as the last 4 parameters used in the "mode 1" command.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",248
	;[249] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",249
	;[250] CONST STACK_BLACK			= $0000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",250
	;[251] CONST STACK_BLUE			= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",251
	;[252] CONST STACK_RED				= $0002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",252
	;[253] CONST STACK_TAN				= $0003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",253
	;[254] CONST STACK_DARKGREEN			= $0004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",254
	;[255] CONST STACK_GREEN			= $0005
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",255
	;[256] CONST STACK_YELLOW			= $0006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",256
	;[257] CONST STACK_WHITE			= $0007
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",257
	;[258] CONST STACK_GREY			= $0008
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",258
	;[259] CONST STACK_CYAN			= $0009
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",259
	;[260] CONST STACK_ORANGE			= $000A
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",260
	;[261] CONST STACK_BROWN			= $000B
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",261
	;[262] CONST STACK_PINK			= $000C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",262
	;[263] CONST STACK_LIGHTBLUE			= $000D
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",263
	;[264] CONST STACK_YELLOWGREEN			= $000E
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",264
	;[265] CONST STACK_PURPLE			= $000F
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",265
	;[266] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",266
	;[267] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",267
	;[268] REM Foreground.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",268
	;[269] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",269
	;[270] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",270
	;[271] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",271
	;[272] REM - Only one foreground colour permitted per background card.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",272
	;[273] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",273
	;[274] CONST CS_BLACK				= $0000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",274
	;[275] CONST CS_BLUE				= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",275
	;[276] CONST CS_RED				= $0002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",276
	;[277] CONST CS_TAN				= $0003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",277
	;[278] CONST CS_DARKGREEN			= $0004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",278
	;[279] CONST CS_GREEN				= $0005
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",279
	;[280] CONST CS_YELLOW				= $0006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",280
	;[281] CONST CS_WHITE				= $0007
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",281
	;[282] CONST CS_GREY				= $1000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",282
	;[283] CONST CS_CYAN				= $1001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",283
	;[284] CONST CS_ORANGE				= $1002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",284
	;[285] CONST CS_BROWN				= $1003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",285
	;[286] CONST CS_PINK				= $1004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",286
	;[287] CONST CS_LIGHTBLUE			= $1005
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",287
	;[288] CONST CS_YELLOWGREEN			= $1006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",288
	;[289] CONST CS_PURPLE				= $1007
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",289
	;[290] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",290
	;[291] CONST CS_CARD_DATA_MASK			= $07F8		' Mask to get the background card's data.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",291
	;[292] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",292
	;[293] CONST CS_ADVANCE			= $2000		' Advance the colour stack by one position.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",293
	;[294] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",294
	;[295] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",295
	;[296] REM Coloured squares mode.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",296
	;[297] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",297
	;[298] REM Notes :
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",298
	;[299] REM - Only available in colour stack mode.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",299
	;[300] REM - Pixels in each BACKTAB card are arranged in the following manner:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",300
	;[301] REM +-------+-------+
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",301
	;[302] REM | Pixel | Pixel |
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",302
	;[303] REM |   0   |   1   !
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",303
	;[304] REM +-------+-------+
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",304
	;[305] REM | Pixel | Pixel |
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",305
	;[306] REM |   2   |   3   !
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",306
	;[307] REM +-------+-------+
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",307
	;[308] REM
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",308
	;[309] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",309
	;[310] CONST CS_COLOUR_SQUARES_ENABLE		=$1000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",310
	;[311] CONST CS_PIX0_BLACK			=0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",311
	;[312] CONST CS_PIX0_BLUE			=1
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",312
	;[313] CONST CS_PIX0_RED			=2
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",313
	;[314] CONST CS_PIX0_TAN			=3
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",314
	;[315] CONST CS_PIX0_DARKGREEN			=4
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",315
	;[316] CONST CS_PIX0_GREEN			=5
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",316
	;[317] CONST CS_PIX0_YELLOW			=6
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",317
	;[318] CONST CS_PIX0_BACKGROUND		=7
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",318
	;[319] CONST CS_PIX1_BLACK			=0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",319
	;[320] CONST CS_PIX1_BLUE			=1*8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",320
	;[321] CONST CS_PIX1_RED			=2*8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",321
	;[322] CONST CS_PIX1_TAN			=3*8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",322
	;[323] CONST CS_PIX1_DARKGREEN			=4*8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",323
	;[324] CONST CS_PIX1_GREEN			=5*8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",324
	;[325] CONST CS_PIX1_YELLOW			=6*8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",325
	;[326] CONST CS_PIX1_BACKGROUND		=7*8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",326
	;[327] CONST CS_PIX2_BLACK			=0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",327
	;[328] CONST CS_PIX2_BLUE			=1*64
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",328
	;[329] CONST CS_PIX2_RED			=2*64
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",329
	;[330] CONST CS_PIX2_TAN			=3*64
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",330
	;[331] CONST CS_PIX2_DARKGREEN			=4*64
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",331
	;[332] CONST CS_PIX2_GREEN			=5*64
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",332
	;[333] CONST CS_PIX2_YELLOW			=6*64
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",333
	;[334] CONST CS_PIX2_BACKGROUND		=7*64
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",334
	;[335] CONST CS_PIX3_BLACK			=0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",335
	;[336] CONST CS_PIX3_BLUE			=$0200
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",336
	;[337] CONST CS_PIX3_RED			=$0400
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",337
	;[338] CONST CS_PIX3_TAN			=$0600
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",338
	;[339] CONST CS_PIX3_DARKGREEN			=$2000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",339
	;[340] CONST CS_PIX3_GREEN			=$2200
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",340
	;[341] CONST CS_PIX3_YELLOW			=$2400
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",341
	;[342] CONST CS_PIX3_BACKGROUND		=$2600
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",342
	;[343] CONST CS_PIX_MASK			=CS_COLOUR_SQUARES_ENABLE+CS_PIX0_BACKGROUND+CS_PIX1_BACKGROUND+CS_PIX2_BACKGROUND+CS_PIX3_BACKGROUND
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",343
	;[344] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",344
	;[345] CONST CS_PIX_X_MIN			=0		' Minimum x coordinate.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",345
	;[346] CONST CS_PIX_X_MAX			=39		' Maximum x coordinate.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",346
	;[347] CONST CS_PIX_Y_MIN			=0		' Minimum Y coordinate.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",347
	;[348] CONST CS_PIX_Y_MAX			=23		' Maximum Y coordinate.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",348
	;[349] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",349
	;[350] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",350
	;[351] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",351
	;[352] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",352
	;[353] REM COLORS - Mode 1 (Foreground Background)
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",353
	;[354] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",354
	;[355] REM Foreground.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",355
	;[356] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",356
	;[357] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",357
	;[358] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",358
	;[359] REM - Only one foreground colour permitted per background card.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",359
	;[360] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",360
	;[361] CONST FG_BLACK				= $0000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",361
	;[362] CONST FG_BLUE				= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",362
	;[363] CONST FG_RED				= $0002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",363
	;[364] CONST FG_TAN				= $0003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",364
	;[365] CONST FG_DARKGREEN			= $0004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",365
	;[366] CONST FG_GREEN				= $0005
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",366
	;[367] CONST FG_YELLOW				= $0006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",367
	;[368] CONST FG_WHITE				= $0007
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",368
	;[369] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",369
	;[370] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",370
	;[371] REM Background.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",371
	;[372] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",372
	;[373] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",373
	;[374] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",374
	;[375] REM - Only one background colour permitted per background card.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",375
	;[376] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",376
	;[377] CONST BG_BLACK				= $0000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",377
	;[378] CONST BG_BLUE				= $0200
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",378
	;[379] CONST BG_RED				= $0400
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",379
	;[380] CONST BG_TAN				= $0600
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",380
	;[381] CONST BG_DARKGREEN			= $2000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",381
	;[382] CONST BG_GREEN				= $2200
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",382
	;[383] CONST BG_YELLOW				= $2400
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",383
	;[384] CONST BG_WHITE				= $2600
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",384
	;[385] CONST BG_GREY				= $1000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",385
	;[386] CONST BG_CYAN				= $1200
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",386
	;[387] CONST BG_ORANGE				= $1400
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",387
	;[388] CONST BG_BROWN				= $1600
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",388
	;[389] CONST BG_PINK				= $3000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",389
	;[390] CONST BG_LIGHTBLUE			= $3200
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",390
	;[391] CONST BG_YELLOWGREEN			= $3400
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",391
	;[392] CONST BG_PURPLE				= $3600
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",392
	;[393] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",393
	;[394] CONST FGBG_CARD_DATA_MASK	= $01F8		' Mask to get the background card's data.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",394
	;[395] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",395
	;[396] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",396
	;[397] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",397
	;[398] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",398
	;[399] REM Sprites.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",399
	;[400] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",400
	;[401] REM Note: For use with "sprite" command.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",401
	;[402] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",402
	;[403] REM X
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",403
	;[404] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",404
	;[405] REM Note: Add these constants to the sprite command's X parameter.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",405
	;[406] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",406
	;[407] CONST HIT				= $0100		' Enable the sprite's collision detection.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",407
	;[408] CONST VISIBLE				= $0200		' Make the sprite visible.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",408
	;[409] CONST ZOOMX2				= $0400		' Make the sprite twice the width.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",409
	;[410] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",410
	;[411] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",411
	;[412] REM Y
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",412
	;[413] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",413
	;[414] REM Note: Add these constants to the sprite command's Y parameter.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",414
	;[415] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",415
	;[416] CONST DOUBLEY				= $0080		' Make a double height sprite (with 2 GRAM cards).
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",416
	;[417] CONST ZOOMY2				= $0100		' Make the sprite twice (x2) the normal height.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",417
	;[418] CONST ZOOMY4				= $0200		' Make the sprite quadruple (x4) the normal height.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",418
	;[419] CONST ZOOMY8				= $0300		' Make the sprite octuple (x8) the normal height.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",419
	;[420] CONST FLIPX				= $0400		' Flip/mirror the sprite in X.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",420
	;[421] CONST FLIPY				= $0800		' Flip/mirror the sprite in Y.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",421
	;[422] CONST MIRROR				= $0C00		' Flip/mirror the sprite in both X and Y.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",422
	;[423] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",423
	;[424] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",424
	;[425] REM A
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",425
	;[426] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",426
	;[427] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",427
	;[428] REM - Combine to create the sprite command's A parameter.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",428
	;[429] REM - Only one colour per sprite.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",429
	;[430] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",430
	;[431] CONST GRAM				= $0800		' Sprite's data is located in GRAM.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",431
	;[432] CONST BEHIND				= $2000		' Sprite is behind the background.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",432
	;[433] CONST SPR_BLACK				= $0000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",433
	;[434] CONST SPR_BLUE				= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",434
	;[435] CONST SPR_RED				= $0002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",435
	;[436] CONST SPR_TAN				= $0003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",436
	;[437] CONST SPR_DARKGREEN			= $0004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",437
	;[438] CONST SPR_GREEN				= $0005
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",438
	;[439] CONST SPR_YELLOW			= $0006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",439
	;[440] CONST SPR_WHITE				= $0007
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",440
	;[441] CONST SPR_GREY				= $1000
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",441
	;[442] CONST SPR_CYAN				= $1001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",442
	;[443] CONST SPR_ORANGE			= $1002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",443
	;[444] CONST SPR_BROWN				= $1003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",444
	;[445] CONST SPR_PINK				= $1004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",445
	;[446] CONST SPR_LIGHTBLUE			= $1005
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",446
	;[447] CONST SPR_YELLOWGREEN			= $1006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",447
	;[448] CONST SPR_PURPLE			= $1007
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",448
	;[449] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",449
	;[450] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",450
	;[451] REM GRAM numbers.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",451
	;[452] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",452
	;[453] REM Note: For use in the sprite command's parameter A.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",453
	;[454] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",454
	;[455] CONST SPR00 				= $0800
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",455
	;[456] CONST SPR01 				= $0808
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",456
	;[457] CONST SPR02 				= $0810
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",457
	;[458] CONST SPR03 				= $0818
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",458
	;[459] CONST SPR04 				= $0820
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",459
	;[460] CONST SPR05 				= $0828
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",460
	;[461] CONST SPR06 				= $0830
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",461
	;[462] CONST SPR07 				= $0838
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",462
	;[463] CONST SPR08 				= $0840
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",463
	;[464] CONST SPR09 				= $0848
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",464
	;[465] CONST SPR10 				= $0850
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",465
	;[466] CONST SPR11 				= $0858
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",466
	;[467] CONST SPR12 				= $0860
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",467
	;[468] CONST SPR13 				= $0868
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",468
	;[469] CONST SPR14 				= $0870
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",469
	;[470] CONST SPR15 				= $0878
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",470
	;[471] CONST SPR16 				= $0880
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",471
	;[472] CONST SPR17 				= $0888
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",472
	;[473] CONST SPR18 				= $0890
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",473
	;[474] CONST SPR19 				= $0898
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",474
	;[475] CONST SPR20 				= $08A0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",475
	;[476] CONST SPR21 				= $08A8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",476
	;[477] CONST SPR22 				= $08B0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",477
	;[478] CONST SPR23 				= $08B8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",478
	;[479] CONST SPR24 				= $08C0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",479
	;[480] CONST SPR25 				= $08C8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",480
	;[481] CONST SPR26 				= $08D0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",481
	;[482] CONST SPR27 				= $08D8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",482
	;[483] CONST SPR28 				= $08E0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",483
	;[484] CONST SPR29 				= $08E8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",484
	;[485] CONST SPR30 				= $08F0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",485
	;[486] CONST SPR31 				= $08F8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",486
	;[487] CONST SPR32 				= $0900
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",487
	;[488] CONST SPR33 				= $0908
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",488
	;[489] CONST SPR34 				= $0910
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",489
	;[490] CONST SPR35 				= $0918
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",490
	;[491] CONST SPR36 				= $0920
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",491
	;[492] CONST SPR37 				= $0928
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",492
	;[493] CONST SPR38 				= $0930
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",493
	;[494] CONST SPR39 				= $0938
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",494
	;[495] CONST SPR40 				= $0940
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",495
	;[496] CONST SPR41 				= $0948
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",496
	;[497] CONST SPR42 				= $0950
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",497
	;[498] CONST SPR43 				= $0958
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",498
	;[499] CONST SPR44 				= $0960
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",499
	;[500] CONST SPR45 				= $0968
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",500
	;[501] CONST SPR46 				= $0970
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",501
	;[502] CONST SPR47 				= $0978
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",502
	;[503] CONST SPR48 				= $0980
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",503
	;[504] CONST SPR49 				= $0988
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",504
	;[505] CONST SPR50 				= $0990
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",505
	;[506] CONST SPR51 				= $0998
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",506
	;[507] CONST SPR52 				= $09A0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",507
	;[508] CONST SPR53 				= $09A8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",508
	;[509] CONST SPR54 				= $09B0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",509
	;[510] CONST SPR55 				= $09B8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",510
	;[511] CONST SPR56 				= $09C0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",511
	;[512] CONST SPR57 				= $09C8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",512
	;[513] CONST SPR58 				= $09D0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",513
	;[514] CONST SPR59 				= $09D8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",514
	;[515] CONST SPR60 				= $09E0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",515
	;[516] CONST SPR61 				= $09E8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",516
	;[517] CONST SPR62 				= $09F0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",517
	;[518] CONST SPR63 				= $09F8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",518
	;[519] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",519
	;[520] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",520
	;[521] REM Sprite collision.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",521
	;[522] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",522
	;[523] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",523
	;[524] REM - For use with variables COL0, COL1, COL2, COL3, COL4, COL5, COL6 and COL7.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",524
	;[525] REM - More than one collision can occur simultaneously.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",525
	;[526] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",526
	;[527] CONST HIT_SPRITE0			= $0001		' Sprite collided with sprite 0.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",527
	;[528] CONST HIT_SPRITE1			= $0002		' Sprite collided with sprite 1.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",528
	;[529] CONST HIT_SPRITE2			= $0004		' Sprite collided with sprite 2.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",529
	;[530] CONST HIT_SPRITE3			= $0008		' Sprite collided with sprite 3.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",530
	;[531] CONST HIT_SPRITE4			= $0010		' Sprite collided with sprite 4.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",531
	;[532] CONST HIT_SPRITE5			= $0020		' Sprite collided with sprite 5.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",532
	;[533] CONST HIT_SPRITE6			= $0040		' Sprite collided with sprite 6.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",533
	;[534] CONST HIT_SPRITE7			= $0080		' Sprite collided with sprite 7.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",534
	;[535] CONST HIT_BACKGROUND			= $0100		' Sprite collided with a background pixel.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",535
	;[536] CONST HIT_BORDER			= $0200		' Sprite collided with the top/bottom/left/right border.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",536
	;[537] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",537
	;[538] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",538
	;[539] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",539
	;[540] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",540
	;[541] REM DISC - Compass.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",541
	;[542] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",542
	;[543] REM   NW         N         NE
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",543
	;[544] REM     \   NNW  |  NNE   /
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",544
	;[545] REM       \      |      /
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",545
	;[546] REM         \    |    /
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",546
	;[547] REM    WNW    \  |  /    ENE
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",547
	;[548] REM             \|/
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",548
	;[549] REM  W ----------+---------- E
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",549
	;[551] REM             /|REM    WSW    /  |  \    ESE
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",551
	;[555] REM         /    |    REM       /      |      REM     /   SSW  |  SSE   REM   SW         S         SE
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",555
	;[556] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",556
	;[557] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",557
	;[558] REM - North points upwards on the hand controller.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",558
	;[559] REM - Directions are listed in a clockwise manner.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",559
	;[560] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",560
	;[561] CONST DISC_NORTH			= $0004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",561
	;[562] CONST DISC_NORTH_NORTH_EAST		= $0014
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",562
	;[563] CONST DISC_NORTH_EAST			= $0016
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",563
	;[564] CONST DISC_EAST_NORTH_EAST		= $0006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",564
	;[565] CONST DISC_EAST				= $0002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",565
	;[566] CONST DISC_EAST_SOUTH_EAST		= $0012
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",566
	;[567] CONST DISC_SOUTH_EAST			= $0013
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",567
	;[568] CONST DISC_SOUTH_SOUTH_EAST		= $0003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",568
	;[569] CONST DISC_SOUTH			= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",569
	;[570] CONST DISC_SOUTH_SOUTH_WEST		= $0011
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",570
	;[571] CONST DISC_SOUTH_WEST			= $0019
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",571
	;[572] CONST DISC_WEST_SOUTH_WEST		= $0009
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",572
	;[573] CONST DISC_WEST				= $0008
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",573
	;[574] CONST DISC_WEST_NORTH_WEST		= $0018
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",574
	;[575] CONST DISC_NORTH_WEST			= $001C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",575
	;[576] CONST DISC_NORTH_NORTH_WEST		= $000C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",576
	;[577] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",577
	;[578] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",578
	;[579] REM DISC - Compass abbreviated versions.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",579
	;[580] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",580
	;[581] CONST DISC_N				= $0004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",581
	;[582] CONST DISC_NNE 				= $0014
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",582
	;[583] CONST DISC_NE				= $0016
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",583
	;[584] CONST DISC_ENE				= $0006
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",584
	;[585] CONST DISC_E				= $0002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",585
	;[586] CONST DISC_ESE				= $0012
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",586
	;[587] CONST DISC_SE				= $0013
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",587
	;[588] CONST DISC_SSE				= $0003
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",588
	;[589] CONST DISC_S				= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",589
	;[590] CONST DISC_SSW				= $0011
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",590
	;[591] CONST DISC_SW				= $0019
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",591
	;[592] CONST DISC_WSW				= $0009
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",592
	;[593] CONST DISC_W				= $0008
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",593
	;[594] CONST DISC_WNW				= $0018
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",594
	;[595] CONST DISC_NW				= $001C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",595
	;[596] CONST DISC_NNW				= $000C
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",596
	;[597] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",597
	;[598] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",598
	;[599] REM DISC - Directions.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",599
	;[600] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",600
	;[601] CONST DISC_UP				= $0004
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",601
	;[602] CONST DISC_UP_RIGHT			= $0016		' Up and right diagonal.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",602
	;[603] CONST DISC_RIGHT			= $0002
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",603
	;[604] CONST DISC_DOWN_RIGHT			= $0013		' Down  and right diagonal.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",604
	;[605] CONST DISC_DOWN				= $0001
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",605
	;[606] CONST DISC_DOWN_LEFT			= $0019		' Down and left diagonal.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",606
	;[607] CONST DISC_LEFT				= $0008
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",607
	;[608] CONST DISC_UP_LEFT			= $001C		' Up and left diagonal.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",608
	;[609] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",609
	;[610] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",610
	;[611] REM DISK - Mask.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",611
	;[612] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",612
	;[613] CONST DISK_MASK				= $001F
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",613
	;[614] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",614
	;[615] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",615
	;[616] REM Controller - Keypad.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",616
	;[617] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",617
	;[618] CONST KEYPAD_0				= 72
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",618
	;[619] CONST KEYPAD_1				= 129
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",619
	;[620] CONST KEYPAD_2				= 65
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",620
	;[621] CONST KEYPAD_3				= 33
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",621
	;[622] CONST KEYPAD_4				= 130
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",622
	;[623] CONST KEYPAD_5				= 66
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",623
	;[624] CONST KEYPAD_6				= 34
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",624
	;[625] CONST KEYPAD_7				= 132
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",625
	;[626] CONST KEYPAD_8				= 68
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",626
	;[627] CONST KEYPAD_9				= 36
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",627
	;[628] CONST KEYPAD_CLEAR			= 136
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",628
	;[629] CONST KEYPAD_ENTER			= 40
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",629
	;[630] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",630
	;[631] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",631
	;[632] REM Controller - Pause buttons (1+9 or 3+7 held down simultaneously).
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",632
	;[633] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",633
	;[634] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",634
	;[635] REM - Key codes for 3+7 and 1+9 are the same (165).
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",635
	;[636] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",636
	;[637] CONST KEYPAD_PAUSE			= (KEYPAD_1 XOR KEYPAD_9)
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",637
	;[638] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",638
	;[639] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",639
	;[640] REM Controller - Side buttons.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",640
	;[641] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",641
	;[642] CONST BUTTON_TOP_LEFT			= $A0		' Top left and top right are the same button.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",642
	;[643] CONST BUTTON_TOP_RIGHT			= $A0		' Note: Bit 6 is low.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",643
	;[644] CONST BUTTON_BOTTOM_LEFT		= $60		' Note: Bit 7 is low.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",644
	;[645] CONST BUTTON_BOTTOM_RIGHT		= $C0		' Note: Bit 5 is low
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",645
	;[646] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",646
	;[647] REM Abbreviated versions.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",647
	;[648] CONST BUTTON_1				= $A0		' Top left or top right.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",648
	;[649] CONST BUTTON_2				= $60		' Bottom left.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",649
	;[650] CONST BUTTON_3				= $C0		' Bottom right.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",650
	;[651] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",651
	;[652] REM Mask.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",652
	;[653] CONST BUTTON_MASK			= $E0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",653
	;[654] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",654
	;[655] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",655
	;[656] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",656
	;[657] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",657
	;[658] REM Programmable Sound Generator (PSG)
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",658
	;[659] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",659
	;[660] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",660
	;[661] REM - For use with the SOUND command
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",661
	;[662] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",662
	;[663] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",663
	;[664] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",664
	;[665] REM Internal sound hardware.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",665
	;[666] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",666
	;[667] CONST PSG_CHANNELA			=0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",667
	;[668] CONST PSG_CHANNELB			=1
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",668
	;[669] CONST PSG_CHANNELC			=2
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",669
	;[670] CONST PSG_ENVELOPE			=3
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",670
	;[671] CONST PSG_MIXER				=4
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",671
	;[672] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",672
	;[673] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",673
	;[674] REM ECS sound hardware.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",674
	;[675] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",675
	;[676] CONST PSG_ECS_CHANNELA			=5
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",676
	;[677] CONST PSG_ECS_CHANNELB			=6
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",677
	;[678] CONST PSG_ECS_CHANNELC			=7
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",678
	;[679] CONST PSG_ECS_ENVELOPE			=8
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",679
	;[680] CONST PSG_ECS_MIXER			=9
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",680
	;[681] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",681
	;[682] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",682
	;[683] REM PSG - Volume control.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",683
	;[684] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",684
	;[685] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",685
	;[686] REM - For use in the volume field of the SOUND command.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",686
	;[687] REM - Internal channels: PSG_CHANNELA, PSG_CHANNELB, PSG_CHANNELC
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",687
	;[688] REM - ECS channels: PSG_ECS_CHANNELA, PSG_ECS_CHANNELB, PSG_ECS_CHANNELC
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",688
	;[689] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",689
	;[690] CONST PSG_VOLUME_MAX			=15	' Maximum channel volume.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",690
	;[691] CONST PSG_ENVELOPE_ENABLE		=48	' Channel volume is controlled by envelope generator.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",691
	;[692] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",692
	;[693] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",693
	;[694] REM PSG - Mixer control.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",694
	;[695] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",695
	;[696] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",696
	;[697] REM - Internal channel: PSG_MIXER
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",697
	;[698] REM - EXS channel: PSG_ECS_MIXER
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",698
	;[699] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",699
	;[700] CONST PSG_TONE_CHANNELA_DISABLE		=$01	' Disable channel A tone.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",700
	;[701] CONST PSG_TONE_CHANNELB_DISABLE		=$02	' Disable channel B tone.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",701
	;[702] CONST PSG_TONE_CHANNELC_DISABLE		=$04	' Disable channel C tone.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",702
	;[703] CONST PSG_NOISE_CHANNELA_DISABLE	=$08	' Disable channel A noise.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",703
	;[704] CONST PSG_NOISE_CHANNELB_DISABLE	=$10	' Disable channel B noise.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",704
	;[705] CONST PSG_NOISE_CHANNELC_DISABLE	=$20	' Disable channel C noise.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",705
	;[706] CONST PSG_MIXER_DEFAULT			=$38 	' All notes enabled. all noise disabled.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",706
	;[707] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",707
	;[708] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",708
	;[709] REM PSG - Envelope control.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",709
	;[710] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",710
	;[711] REM Notes:
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",711
	;[712] REM - Internal channel: PSG_ENVELOPE
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",712
	;[713] REM - EXS channel: PSG_ECS_ENVELOPE
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",713
	;[714] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",714
	;[715] CONST PSG_ENVELOPE_HOLD					=$01
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",715
	;[716] CONST PSG_ENVELOPE_ALTERNATE				=$02
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",716
	;[717] CONST PSG_ENVELOPE_ATTACK				=$04
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",717
	;[718] CONST PSG_ENVELOPE_CONTINUE				=$08
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",718
	;[719] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_OFF	=$00 '\______
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",719
	;[720] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_OFF		=$04 '/______
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",720
	;[723] CONST PSG_ENVELOPE_CYCLE_RAMP_DOWN_SAWTOOTH		=$08 '\\\\\\CONST PSG_ENVELOPE_CYCLE_RAMP_DOWN_TRIANGLE		=$0A '\/\/\/CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_MAX	=$0B '\^^^^^^
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",723
	;[724] CONST PSG_ENVELOPE_CYCLE_RAMP_UP_SAWTOOTH		=$0C '///////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",724
	;[725] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_MAX		=$0D '/^^^^^^
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",725
	;[726] CONST PSG_ENVELOPE_CYCLE_RAMP_UP_TRIANGLE		=$0E '/\/\/\/
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",726
	;[727] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",727
	;[728] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",728
	;[729] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",729
	;[730] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",730
	;[731] REM Useful functions.
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",731
	;[732] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",732
	;[733] DEF FN screenpos(aColumn, aRow)		=          (((aRow)*BACKGROUND_COLUMNS)+(aColumn))
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",733
	;[734] DEF FN screenaddr(aColumn, aRow)	= (BACKTAB_ADDR+(((aRow)*BACKGROUND_COLUMNS)+(aColumn)))
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",734
	;[735] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",735
	;[736] DEF FN setspritex(aSpriteNo,anXPosition)= #mobshadow(aSpriteNo  )=(#mobshadow(aSpriteNo  ) and $ff00)+anXPosition
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",736
	;[737] DEF FN setspritey(aSpriteNo,aYPosition)	= #mobshadow(aSpriteNo+8)=(#mobshadow(aSpriteNo+8) and $ff80)+aYPosition
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",737
	;[738] DEF FN resetsprite(aSpriteNo)		= sprite aSpriteNo, 0, 0, 0
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",738
	;[739] DEF FN togglespritevisible(aSpriteNo)	= #mobshadow(aSpriteNo   )=#mobshadow(aSpriteNo)    xor VISIBLE
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",739
	;[740] DEF FN togglespritehit(aSpriteNo)	= #mobshadow(aSpriteNo   )=#mobshadow(aSpriteNo)    xor HIT
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",740
	;[741] DEF FN togglespritebehind(aSpriteNo)	= #mobshadow(aSpriteNo+16)=#mobshadow(aSpriteNo+16) xor BEHIND
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",741
	;[742] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",742
	;[743] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",743
	;[744] 
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",744
	;[745] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",745
	;[746] REM END
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",746
	;[747] REM -------------------------------------------------------------------------
	SRCFILE "/Users/tejsaikakumanu/Documents/IntyBASIC-SDK/lib/constants.bas",747
	;ENDFILE
	;FILE Maze.bas
	;[10] 
	SRCFILE "Maze.bas",10
	;[11] 	WAIT
	SRCFILE "Maze.bas",11
	CALL _wait
	;[12] 	DEFINE DEF00,4,drawings
	SRCFILE "Maze.bas",12
	CLRR R0
	MVO R0,_gram_target
	MVII #4,R0
	MVO R0,_gram_total
	MVII #label_DRAWINGS,R0
	MVO R0,_gram_bitmap
	;[13] 	ON FRAME GOSUB FRAME_UPDATE
	SRCFILE "Maze.bas",13
	;[14] 	TIMER = 0
	SRCFILE "Maze.bas",14
	CLRR R0
	MVO R0,var_TIMER
	;[15] 
	SRCFILE "Maze.bas",15
	;[16] 
	SRCFILE "Maze.bas",16
	;[17] restart:
	SRCFILE "Maze.bas",17
	; RESTART
label_RESTART:	;[18] 
	SRCFILE "Maze.bas",18
	;[19] 	IF #score <> 0 THEN
	SRCFILE "Maze.bas",19
	MVI var_&SCORE,R0
	TSTR R0
	BEQ T1
	;[20] 		GOSUB effect1
	SRCFILE "Maze.bas",20
	CALL label_EFFECT1
	;[21] 	END IF
	SRCFILE "Maze.bas",21
T1:
	;[22] 	
	SRCFILE "Maze.bas",22
	;[23] 	MODE SCREEN_CS, STACK_BLACK, STACK_BLACK, STACK_BLACK, STACK_BLACK
	SRCFILE "Maze.bas",23
	CLRR R0
	MVO R0,_color
	MVII #2,R0
	MVO R0,_mode_select
	;[24] 	WAIT
	SRCFILE "Maze.bas",24
	CALL _wait
	;[25] 	
	SRCFILE "Maze.bas",25
	;[26] 	PLAY SIMPLE
	SRCFILE "Maze.bas",26
	MVII #3,R3
	MVO R3,_music_mode
	;[27] 	PLAY tune
	SRCFILE "Maze.bas",27
	MVII #label_TUNE,R0
	CALL _play_music
	;[28] 	room=0
	SRCFILE "Maze.bas",28
	CLRR R0
	MVO R0,var_ROOM
	;[29] 	#score=0
	SRCFILE "Maze.bas",29
	MVO R0,var_&SCORE
	;[30] 
	SRCFILE "Maze.bas",30
	;[31] 	
	SRCFILE "Maze.bas",31
	;[32] 
	SRCFILE "Maze.bas",32
	;[33] load_room:
	SRCFILE "Maze.bas",33
	; LOAD_ROOM
label_LOAD_ROOM:	;[34] 
	SRCFILE "Maze.bas",34
	;[35] 	
	SRCFILE "Maze.bas",35
	;[36] 
	SRCFILE "Maze.bas",36
	;[37] 	IF #score = 5 THEN
	SRCFILE "Maze.bas",37
	MVI var_&SCORE,R0
	CMPI #5,R0
	BNE T2
	;[38] 		CLS
	SRCFILE "Maze.bas",38
	CALL CLRSCR
	;[39] 		PRINT AT SCREENPOS(4, 5) COLOR CS_BLUE, "Well Done!"
	SRCFILE "Maze.bas",39
	MVII #616,R0
	MVO R0,_screen
	MVII #1,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #440,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #912,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #608,R0
	MVO@ R0,R4
	XORI #288,R0
	MVO@ R0,R4
	XORI #856,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #544,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[40] 		
	SRCFILE "Maze.bas",40
	;[41] 		
	SRCFILE "Maze.bas",41
	;[42] 
	SRCFILE "Maze.bas",42
	;[43] 		MODE SCREEN_CS, STACK_WHITE, STACK_WHITE, STACK_WHITE, STACK_WHITE
	SRCFILE "Maze.bas",43
	MVII #30583,R0
	MVO R0,_color
	MVII #2,R0
	MVO R0,_mode_select
	;[44] 		WAIT
	SRCFILE "Maze.bas",44
	CALL _wait
	;[45] 		
	SRCFILE "Maze.bas",45
	;[46] 		PLAY OFF
	SRCFILE "Maze.bas",46
	CLRR R0
	CALL _play_music
	;[47] 			
	SRCFILE "Maze.bas",47
	;[48] 	
	SRCFILE "Maze.bas",48
	;[49] 		IF CONT <> 0 AND TIMER = 0 THEN
	SRCFILE "Maze.bas",49
	MVI 510,R0
	XOR 511,R0
	MVII #65535,R0
	BNE T4
	INCR R0
T4:
	MVI var_TIMER,R1
	TSTR R1
	MVII #65535,R1
	BEQ T5
	INCR R1
T5:
	ANDR R1,R0
	BEQ T3
	;[50] 			GOTO restart
	SRCFILE "Maze.bas",50
	B label_RESTART
	;[51] 		END IF
	SRCFILE "Maze.bas",51
T3:
	;[52] 		GOTO load_room
	SRCFILE "Maze.bas",52
	B label_LOAD_ROOM
	;[53] 	END IF
	SRCFILE "Maze.bas",53
T2:
	;[54] 	
	SRCFILE "Maze.bas",54
	;[55] 
	SRCFILE "Maze.bas",55
	;[56] 	PLAY OFF
	SRCFILE "Maze.bas",56
	CLRR R0
	CALL _play_music
	;[57] 
	SRCFILE "Maze.bas",57
	;[58] 	IF #score <> 0 THEN
	SRCFILE "Maze.bas",58
	MVI var_&SCORE,R0
	TSTR R0
	BEQ T6
	;[59] 		GOSUB effect3
	SRCFILE "Maze.bas",59
	CALL label_EFFECT3
	;[60] 	END IF
	SRCFILE "Maze.bas",60
T6:
	;[61] 
	SRCFILE "Maze.bas",61
	;[62] 	PLAY SIMPLE
	SRCFILE "Maze.bas",62
	MVII #3,R3
	MVO R3,_music_mode
	;[63] 	PLAY TUNE
	SRCFILE "Maze.bas",63
	MVII #label_TUNE,R0
	CALL _play_music
	;[64] 
	SRCFILE "Maze.bas",64
	;[65] 
	SRCFILE "Maze.bas",65
	;[66] 	IF room = 0 THEN RESTORE room0 : #monster = SPR03 + SPR_GREEN
	SRCFILE "Maze.bas",66
	MVI var_ROOM,R0
	TSTR R0
	BNE T7
	MVII #label_ROOM0,R4
	MVO R4,_read
	MVII #2077,R0
	MVO R0,var_&MONSTER
T7:
	;[67] 	IF room = 1 THEN RESTORE room1 : #monster = SPR00 + SPR_GREEN
	SRCFILE "Maze.bas",67
	MVI var_ROOM,R0
	CMPI #1,R0
	BNE T8
	MVII #label_ROOM1,R4
	MVO R4,_read
	MVII #2053,R0
	MVO R0,var_&MONSTER
T8:
	;[68] 	IF room = 2 THEN RESTORE room2 : #monster = SPR03 + SPR_GREEN
	SRCFILE "Maze.bas",68
	MVI var_ROOM,R0
	CMPI #2,R0
	BNE T9
	MVII #label_ROOM2,R4
	MVO R4,_read
	MVII #2077,R0
	MVO R0,var_&MONSTER
T9:
	;[69] 	IF room = 3 THEN RESTORE room3 : #monster = SPR00 + SPR_GREEN
	SRCFILE "Maze.bas",69
	MVI var_ROOM,R0
	CMPI #3,R0
	BNE T10
	MVII #label_ROOM3,R4
	MVO R4,_read
	MVII #2053,R0
	MVO R0,var_&MONSTER
T10:
	;[70] 	IF room = 4 THEN RESTORE room4 : #monster = SPR03 + SPR_GREEN
	SRCFILE "Maze.bas",70
	MVI var_ROOM,R0
	CMPI #4,R0
	BNE T11
	MVII #label_ROOM4,R4
	MVO R4,_read
	MVII #2077,R0
	MVO R0,var_&MONSTER
T11:
	;[71] 
	SRCFILE "Maze.bas",71
	;[72] 	' Deactivate sprites
	SRCFILE "Maze.bas",72
	;[73] 	resetsprite(0)
	SRCFILE "Maze.bas",73
	CLRR R0
	MVO R0,_mobs
	MVO R0,_mobs+8
	NOP
	MVO R0,_mobs+16
	;[74] 	WAIT    ' Wait to reset collision bits
	SRCFILE "Maze.bas",74
	CALL _wait
	;[75] 
	SRCFILE "Maze.bas",75
	;[76] 	'
	SRCFILE "Maze.bas",76
	;[77] 	' Clean screen
	SRCFILE "Maze.bas",77
	;[78] 	'
	SRCFILE "Maze.bas",78
	;[79] 	CLS
	SRCFILE "Maze.bas",79
	CALL CLRSCR
	;[80] 
	SRCFILE "Maze.bas",80
	;[81] 	'
	SRCFILE "Maze.bas",81
	;[82] 	' Draw current score in vertical
	SRCFILE "Maze.bas",82
	;[83] 	'
	SRCFILE "Maze.bas",83
	;[84] 	PRINT AT (SCREENPOS(0, 0)), "L"
	SRCFILE "Maze.bas",84
	MVII #512,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #352,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[85] 	PRINT AT (SCREENPOS(0, 1)), "V"
	SRCFILE "Maze.bas",85
	MVII #532,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #432,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[86] 	PRINT AT (SCREENPOS(0, 2)), "L"
	SRCFILE "Maze.bas",86
	MVII #552,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #352,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[87] 	PRINT AT (SCREENPOS(0, 3)),(#score%10+16)*8+6
	SRCFILE "Maze.bas",87
	MVII #572,R0
	MVO R0,_screen
	MVI var_&SCORE,R0
T12:
	SUBI #10,R0
	BC T12
	ADDI #26,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[88] 	PRINT COLOR CS_BLUE
	SRCFILE "Maze.bas",88
	MVII #1,R0
	MVO R0,_color
	;[89] 
	SRCFILE "Maze.bas",89
	;[90] 	'
	SRCFILE "Maze.bas",90
	;[91] 	' Draw room line per line
	SRCFILE "Maze.bas",91
	;[92] 	' Extract bit per bit of value to signal labyrinth value
	SRCFILE "Maze.bas",92
	;[93] 	'
	SRCFILE "Maze.bas",93
	;[94] 	FOR y = 0 TO 11
	SRCFILE "Maze.bas",94
	CLRR R0
	MVO R0,var_Y
T13:
	;[95] 		READ #line
	SRCFILE "Maze.bas",95
	MVI _read,R4
	MVI@ R4,R0
	MVO R4,_read
	MVO R0,var_&LINE
	;[96] 		FOR x = 0 TO 15
	SRCFILE "Maze.bas",96
	CLRR R0
	MVO R0,var_X
T14:
	;[97] 			IF #line AND $8000 THEN PRINT AT y*20+x+2,"\95"
	SRCFILE "Maze.bas",97
	MVI var_&LINE,R0
	ANDI #32768,R0
	BEQ T15
	MVI var_Y,R0
	MULT R0,R4,20
	ADD var_X,R0
	ADDI #514,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #760,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
T15:
	;[98] 			#line = #line * 2
	SRCFILE "Maze.bas",98
	MVI var_&LINE,R0
	SLL R0,1
	MVO R0,var_&LINE
	;[99] 		NEXT x
	SRCFILE "Maze.bas",99
	MVI var_X,R0
	INCR R0
	MVO R0,var_X
	CMPI #15,R0
	BLE T14
	;[100] 	NEXT y
	SRCFILE "Maze.bas",100
	MVI var_Y,R0
	INCR R0
	MVO R0,var_Y
	CMPI #11,R0
	BLE T13
	;[101] 
	SRCFILE "Maze.bas",101
	;[102] 	'
	SRCFILE "Maze.bas",102
	;[103] 	' Setup some random barzacks(deleted)
	SRCFILE "Maze.bas",103
	;[104] 	'
	SRCFILE "Maze.bas",104
	;[105] 
	SRCFILE "Maze.bas",105
	;[106] 	'
	SRCFILE "Maze.bas",106
	;[107] 	' Player start
	SRCFILE "Maze.bas",107
	;[108] 	'
	SRCFILE "Maze.bas",108
	;[109] 	x1 = 32
	SRCFILE "Maze.bas",109
	MVII #32,R0
	MVO R0,var_X1
	;[110] 	y1 = 28
	SRCFILE "Maze.bas",110
	MVII #28,R0
	MVO R0,var_Y1
	;[111] 
	SRCFILE "Maze.bas",111
	;[112] 	room = room + 1
	SRCFILE "Maze.bas",112
	MVI var_ROOM,R0
	INCR R0
	MVO R0,var_ROOM
	;[113] 	IF room = 5 THEN room = 0
	SRCFILE "Maze.bas",113
	MVI var_ROOM,R0
	CMPI #5,R0
	BNE T16
	CLRR R0
	MVO R0,var_ROOM
T16:
	;[114] 
	SRCFILE "Maze.bas",114
	;[115] DIRECTION = 0
	SRCFILE "Maze.bas",115
	CLRR R0
	MVO R0,var_DIRECTION
	;[116] 
	SRCFILE "Maze.bas",116
	;[117] loop:
	SRCFILE "Maze.bas",117
	; LOOP
label_LOOP:	;[118] 	WAIT
	SRCFILE "Maze.bas",118
	CALL _wait
	;[119] 
	SRCFILE "Maze.bas",119
	;[120] 	'
	SRCFILE "Maze.bas",120
	;[121] 	' Update MOBs
	SRCFILE "Maze.bas",121
	;[122] 	'
	SRCFILE "Maze.bas",122
	;[123] 	
	SRCFILE "Maze.bas",123
	;[124] 
	SRCFILE "Maze.bas",124
	;[125] 	'
	SRCFILE "Maze.bas",125
	;[126] 	
	SRCFILE "Maze.bas",126
	;[127] 	
	SRCFILE "Maze.bas",127
	;[128] 
	SRCFILE "Maze.bas",128
	;[129] 	' Check for movement
	SRCFILE "Maze.bas",129
	;[130] 	IF COL0 AND HIT_BACKGROUND THEN
	SRCFILE "Maze.bas",130
	MVI _col0,R0
	ANDI #256,R0
	BEQ T17
	;[131] 		GOSUB effect2
	SRCFILE "Maze.bas",131
	CALL label_EFFECT2
	;[132] 
	SRCFILE "Maze.bas",132
	;[133] 	ELSE IF CONT1.UP THEN 
	SRCFILE "Maze.bas",133
	B T18
T17:
	MVI 511,R0
	XORI #255,R0
	ANDI #4,R0
	BEQ T19
	;[134] 		IF Y1>0 THEN 
	SRCFILE "Maze.bas",134
	MVI var_Y1,R0
	CMPI #0,R0
	BLE T20
	;[135] 			Y1=Y1-1
	SRCFILE "Maze.bas",135
	DECR R0
	MVO R0,var_Y1
	;[136] 			DIRECTION = 1
	SRCFILE "Maze.bas",136
	MVII #1,R0
	MVO R0,var_DIRECTION
	;[137] 		END IF
	SRCFILE "Maze.bas",137
T20:
	;[138] 	
	SRCFILE "Maze.bas",138
	;[139] 	ELSE IF CONT1.DOWN THEN 
	SRCFILE "Maze.bas",139
	B T21
T19:
	MVI 511,R0
	XORI #255,R0
	ANDI #1,R0
	BEQ T22
	;[140] 		IF Y1<104 THEN 
	SRCFILE "Maze.bas",140
	MVI var_Y1,R0
	CMPI #104,R0
	BGE T23
	;[141] 			Y1=Y1+1
	SRCFILE "Maze.bas",141
	INCR R0
	MVO R0,var_Y1
	;[142] 			DIRECTION = 2
	SRCFILE "Maze.bas",142
	MVII #2,R0
	MVO R0,var_DIRECTION
	;[143] 		END IF
	SRCFILE "Maze.bas",143
T23:
	;[144] 	
	SRCFILE "Maze.bas",144
	;[145] 		
	SRCFILE "Maze.bas",145
	;[146] 	ELSE IF CONT1.LEFT THEN 
	SRCFILE "Maze.bas",146
	B T24
T22:
	MVI 511,R0
	XORI #255,R0
	ANDI #8,R0
	BEQ T25
	;[147] 		IF X1>0 THEN 
	SRCFILE "Maze.bas",147
	MVI var_X1,R0
	CMPI #0,R0
	BLE T26
	;[148] 			X1=X1-1
	SRCFILE "Maze.bas",148
	DECR R0
	MVO R0,var_X1
	;[149] 			DIRECTION = 3
	SRCFILE "Maze.bas",149
	MVII #3,R0
	MVO R0,var_DIRECTION
	;[150] 		END IF
	SRCFILE "Maze.bas",150
T26:
	;[151] 	
	SRCFILE "Maze.bas",151
	;[152] 	ELSE IF CONT1.RIGHT THEN 
	SRCFILE "Maze.bas",152
	B T27
T25:
	MVI 511,R0
	XORI #255,R0
	ANDI #2,R0
	BEQ T28
	;[153] 		IF X1<168 THEN 
	SRCFILE "Maze.bas",153
	MVI var_X1,R0
	CMPI #168,R0
	BGE T29
	;[154] 			X1=X1+1
	SRCFILE "Maze.bas",154
	INCR R0
	MVO R0,var_X1
	;[155] 			DIRECTION = 4
	SRCFILE "Maze.bas",155
	MVII #4,R0
	MVO R0,var_DIRECTION
	;[156] 		END IF
	SRCFILE "Maze.bas",156
T29:
	;[157] 	END IF
	SRCFILE "Maze.bas",157
T28:
	;[158] 	END IF
	SRCFILE "Maze.bas",158
T27:
	;[159] 	END IF
	SRCFILE "Maze.bas",159
T24:
	;[160] 	END IF
	SRCFILE "Maze.bas",160
T21:
	;[161] 	END IF
	SRCFILE "Maze.bas",161
T18:
	;[162] 
	SRCFILE "Maze.bas",162
	;[163] 	SPRITE 0,X1+HIT+VISIBLE,Y1+ZOOMY1,SPR02 + SPR_RED ' Our hero
	SRCFILE "Maze.bas",163
	MVI var_X1,R0
	ADDI #768,R0
	MVO R0,_mobs
	MVI var_Y1,R0
	ADD var_ZOOMY1,R0
	MVO R0,_mobs+8
	MVII #2066,R0
	MVO R0,_mobs+16
	;[164] 	WAIT
	SRCFILE "Maze.bas",164
	CALL _wait
	;[165] 	
	SRCFILE "Maze.bas",165
	;[166] 
	SRCFILE "Maze.bas",166
	;[167] 	IF COL0 AND HIT_BACKGROUND THEN 
	SRCFILE "Maze.bas",167
	MVI _col0,R0
	ANDI #256,R0
	BEQ T30
	;[168] 		IF DIRECTION = 1 THEN
	SRCFILE "Maze.bas",168
	MVI var_DIRECTION,R0
	CMPI #1,R0
	BNE T31
	;[169] 			Y1 = Y1 + 1
	SRCFILE "Maze.bas",169
	MVI var_Y1,R0
	INCR R0
	MVO R0,var_Y1
	;[170] 		END IF
	SRCFILE "Maze.bas",170
T31:
	;[171] 		IF DIRECTION = 2 THEN
	SRCFILE "Maze.bas",171
	MVI var_DIRECTION,R0
	CMPI #2,R0
	BNE T32
	;[172] 			Y1 = Y1 - 1
	SRCFILE "Maze.bas",172
	MVI var_Y1,R0
	DECR R0
	MVO R0,var_Y1
	;[173] 		END IF
	SRCFILE "Maze.bas",173
T32:
	;[174] 		IF DIRECTION = 3 THEN
	SRCFILE "Maze.bas",174
	MVI var_DIRECTION,R0
	CMPI #3,R0
	BNE T33
	;[175] 			X1 = X1 + 1
	SRCFILE "Maze.bas",175
	MVI var_X1,R0
	INCR R0
	MVO R0,var_X1
	;[176] 		END IF
	SRCFILE "Maze.bas",176
T33:
	;[177] 		IF DIRECTION = 4 THEN
	SRCFILE "Maze.bas",177
	MVI var_DIRECTION,R0
	CMPI #4,R0
	BNE T34
	;[178] 			X1 = X1 - 1
	SRCFILE "Maze.bas",178
	MVI var_X1,R0
	DECR R0
	MVO R0,var_X1
	;[179] 		END IF
	SRCFILE "Maze.bas",179
T34:
	;[180] 
	SRCFILE "Maze.bas",180
	;[181] 		SPRITE 0,X1+HIT+VISIBLE,Y1ZOOMY1,SPR02 + SPR_RED ' Our hero	
	SRCFILE "Maze.bas",181
	MVI var_X1,R0
	ADDI #768,R0
	MVO R0,_mobs
	MVI var_Y1ZOOMY1,R0
	MVO R0,_mobs+8
	MVII #2066,R0
	MVO R0,_mobs+16
	;[182] 		WAIT
	SRCFILE "Maze.bas",182
	CALL _wait
	;[183] 	END IF
	SRCFILE "Maze.bas",183
T30:
	;[184] 
	SRCFILE "Maze.bas",184
	;[185] 
	SRCFILE "Maze.bas",185
	;[186] 
	SRCFILE "Maze.bas",186
	;[187] 	' Check for change of room
	SRCFILE "Maze.bas",187
	;[188] 	IF Y1<8 OR X1<24 OR X1>144 OR Y1>96 THEN 
	SRCFILE "Maze.bas",188
	MVI var_Y1,R0
	CMPI #8,R0
	MVII #65535,R0
	BLT T36
	INCR R0
T36:
	MVI var_X1,R1
	CMPI #24,R1
	MVII #65535,R1
	BLT T37
	INCR R1
T37:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	MVI var_X1,R1
	CMPI #144,R1
	MVII #65535,R1
	BGT T38
	INCR R1
T38:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	MVI var_Y1,R1
	CMPI #96,R1
	MVII #65535,R1
	BGT T39
	INCR R1
T39:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T35
	;[189] 		#score=#score+1
	SRCFILE "Maze.bas",189
	MVI var_&SCORE,R0
	INCR R0
	MVO R0,var_&SCORE
	;[190] 		TIMER = 900
	SRCFILE "Maze.bas",190
	MVII #900,R0
	MVO R0,var_TIMER
	;[191] 		GOTO load_room
	SRCFILE "Maze.bas",191
	B label_LOAD_ROOM
	;[192] 	END IF
	SRCFILE "Maze.bas",192
T35:
	;[193] 
	SRCFILE "Maze.bas",193
	;[194] 
	SRCFILE "Maze.bas",194
	;[195] 	' Barzacks displacement
	SRCFILE "Maze.bas",195
	;[196] 	IF FRAME AND 7 THEN GOTO loop
	SRCFILE "Maze.bas",196
	MVI _frame,R0
	ANDI #7,R0
	BNE label_LOOP
	;[197] 	IF Y2=0 THEN GOTO avoid1
	SRCFILE "Maze.bas",197
	MVI var_Y2,R0
	TSTR R0
	BEQ label_AVOID1
	;[198] 	IF X1<>X2 THEN IF X1<X2 THEN X2=X2-1 ELSE X2=X2+1
	SRCFILE "Maze.bas",198
	MVI var_X1,R0
	CMP var_X2,R0
	BEQ T42
	CMP var_X2,R0
	BGE T43
	MVI var_X2,R0
	DECR R0
	MVO R0,var_X2
	B T44
T43:
	MVI var_X2,R0
	INCR R0
	MVO R0,var_X2
T44:
T42:
	;[199] 	IF Y1<>Y2 THEN IF Y1<Y2 THEN Y2=Y2-1 ELSE Y2=Y2+1
	SRCFILE "Maze.bas",199
	MVI var_Y1,R0
	CMP var_Y2,R0
	BEQ T45
	CMP var_Y2,R0
	BGE T46
	MVI var_Y2,R0
	DECR R0
	MVO R0,var_Y2
	B T47
T46:
	MVI var_Y2,R0
	INCR R0
	MVO R0,var_Y2
T47:
T45:
	;[200] avoid1:
	SRCFILE "Maze.bas",200
	; AVOID1
label_AVOID1:	;[201] 	IF Y3=0 THEN GOTO avoid2
	SRCFILE "Maze.bas",201
	MVI var_Y3,R0
	TSTR R0
	BEQ label_AVOID2
	;[202] 	IF X1<>X3 THEN IF X1<X3 THEN X3=X3-1 ELSE X3=X3+1
	SRCFILE "Maze.bas",202
	MVI var_X1,R0
	CMP var_X3,R0
	BEQ T49
	CMP var_X3,R0
	BGE T50
	MVI var_X3,R0
	DECR R0
	MVO R0,var_X3
	B T51
T50:
	MVI var_X3,R0
	INCR R0
	MVO R0,var_X3
T51:
T49:
	;[203] 	IF Y1<>Y3 THEN IF Y1<Y3 THEN Y3=Y3-1 ELSE Y3=Y3+1
	SRCFILE "Maze.bas",203
	MVI var_Y1,R0
	CMP var_Y3,R0
	BEQ T52
	CMP var_Y3,R0
	BGE T53
	MVI var_Y3,R0
	DECR R0
	MVO R0,var_Y3
	B T54
T53:
	MVI var_Y3,R0
	INCR R0
	MVO R0,var_Y3
T54:
T52:
	;[204] avoid2:
	SRCFILE "Maze.bas",204
	; AVOID2
label_AVOID2:	;[205] 	IF Y4=0 THEN GOTO avoid3
	SRCFILE "Maze.bas",205
	MVI var_Y4,R0
	TSTR R0
	BEQ label_AVOID3
	;[206] 	IF X1<>X4 THEN IF X1<X4 THEN X4=X4-1 ELSE X4=X4+1
	SRCFILE "Maze.bas",206
	MVI var_X1,R0
	CMP var_X4,R0
	BEQ T56
	CMP var_X4,R0
	BGE T57
	MVI var_X4,R0
	DECR R0
	MVO R0,var_X4
	B T58
T57:
	MVI var_X4,R0
	INCR R0
	MVO R0,var_X4
T58:
T56:
	;[207] 	IF Y1<>Y4 THEN IF Y1<Y4 THEN Y4=Y4-1 ELSE Y4=Y4+1
	SRCFILE "Maze.bas",207
	MVI var_Y1,R0
	CMP var_Y4,R0
	BEQ T59
	CMP var_Y4,R0
	BGE T60
	MVI var_Y4,R0
	DECR R0
	MVO R0,var_Y4
	B T61
T60:
	MVI var_Y4,R0
	INCR R0
	MVO R0,var_Y4
T61:
T59:
	;[208] avoid3:
	SRCFILE "Maze.bas",208
	; AVOID3
label_AVOID3:	;[209] 	IF Y5=0 THEN GOTO avoid4
	SRCFILE "Maze.bas",209
	MVI var_Y5,R0
	TSTR R0
	BEQ label_AVOID4
	;[210] 	IF X1<>X5 THEN IF X1<X5 THEN X5=X5-1 ELSE X5=X5+1
	SRCFILE "Maze.bas",210
	MVI var_X1,R0
	CMP var_X5,R0
	BEQ T63
	CMP var_X5,R0
	BGE T64
	MVI var_X5,R0
	DECR R0
	MVO R0,var_X5
	B T65
T64:
	MVI var_X5,R0
	INCR R0
	MVO R0,var_X5
T65:
T63:
	;[211] 	IF Y1<>Y5 THEN IF Y1<Y5 THEN Y5=Y5-1 ELSE Y5=Y5+1
	SRCFILE "Maze.bas",211
	MVI var_Y1,R0
	CMP var_Y5,R0
	BEQ T66
	CMP var_Y5,R0
	BGE T67
	MVI var_Y5,R0
	DECR R0
	MVO R0,var_Y5
	B T68
T67:
	MVI var_Y5,R0
	INCR R0
	MVO R0,var_Y5
T68:
T66:
	;[212] avoid4:
	SRCFILE "Maze.bas",212
	; AVOID4
label_AVOID4:	;[213] 	GOTO loop
	SRCFILE "Maze.bas",213
	B label_LOOP
	;[214] 
	SRCFILE "Maze.bas",214
	;[215] 
	SRCFILE "Maze.bas",215
	;[216] barzack:	PROCEDURE
	SRCFILE "Maze.bas",216
	; BARZACK
label_BARZACK:	PROC
	BEGIN
	;[217] 
	SRCFILE "Maze.bas",217
	;[218] 	DO
	SRCFILE "Maze.bas",218
T69:
	;[219] 		WAIT
	SRCFILE "Maze.bas",219
	CALL _wait
	;[220] 		X = RAND % 16
	SRCFILE "Maze.bas",220
	MVI _rand,R0
	ANDI #15,R0
	MVO R0,var_X
	;[221] 	LOOP WHILE #BACKTAB(Y * BACKGROUND_COLUMNS + X + 2)
	SRCFILE "Maze.bas",221
	MVII #Q2+2,R1
	MVI var_Y,R2
	MULT R2,R4,20
	ADD var_X,R2
	ADDR R2,R1
	MVI@ R1,R0
	TSTR R0
	BEQ T71
	B T69
T71:
	;[222] 
	SRCFILE "Maze.bas",222
	;[223] 	result = (x + 2) * 8 + 8
	SRCFILE "Maze.bas",223
	MVI var_X,R0
	ADDI #2,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #8,R0
	MVO R0,var_RESULT
	;[224] 
	SRCFILE "Maze.bas",224
	;[225] 	END
	SRCFILE "Maze.bas",225
	RETURN
	ENDP
	;[226] 
	SRCFILE "Maze.bas",226
	;[227] 	'
	SRCFILE "Maze.bas",227
	;[228] 	' Definition of rooms
	SRCFILE "Maze.bas",228
	;[229] 	'
	SRCFILE "Maze.bas",229
	;[230] 	' Uses binary numbers to form a 16-bit value
	SRCFILE "Maze.bas",230
	;[231] 	' (the maximum fitting a DATA value)
	SRCFILE "Maze.bas",231
	;[232] 	'
	SRCFILE "Maze.bas",232
	;[233] FRAME_UPDATE:	PROCEDURE
	SRCFILE "Maze.bas",233
	; FRAME_UPDATE
label_FRAME_UPDATE:	PROC
	BEGIN
	;[234] 
	SRCFILE "Maze.bas",234
	;[235] 		IF TIMER > 0 THEN
	SRCFILE "Maze.bas",235
	MVI var_TIMER,R0
	CMPI #0,R0
	BLE T72
	;[236] 			TIMER = TIMER - 1
	SRCFILE "Maze.bas",236
	DECR R0
	MVO R0,var_TIMER
	;[237] 		END IF
	SRCFILE "Maze.bas",237
T72:
	;[238] 
	SRCFILE "Maze.bas",238
	;[239] 		END
	SRCFILE "Maze.bas",239
	RETURN
	ENDP
	;[240] 
	SRCFILE "Maze.bas",240
	;[241] reset_sound:	PROCEDURE
	SRCFILE "Maze.bas",241
	; RESET_SOUND
label_RESET_SOUND:	PROC
	BEGIN
	;[242] 	SOUND 0,1,0
	SRCFILE "Maze.bas",242
	MVII #1,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	CLRR R0
	MVO R0,507
	;[243] 	SOUND 1,1,0
	SRCFILE "Maze.bas",243
	MVII #1,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	CLRR R0
	MVO R0,508
	;[244] 	SOUND 2,1,0
	SRCFILE "Maze.bas",244
	MVII #1,R0
	MVO R0,498
	SWAP R0
	MVO R0,502
	CLRR R0
	MVO R0,509
	;[245] 	SOUND 4,,$38
	SRCFILE "Maze.bas",245
	MVII #56,R0
	MVO R0,504
	;[246] 	RETURN
	SRCFILE "Maze.bas",246
	RETURN
	;[247] 	END
	SRCFILE "Maze.bas",247
	ENDP
	;[248] 
	SRCFILE "Maze.bas",248
	;[249] effect1:	PROCEDURE
	SRCFILE "Maze.bas",249
	; EFFECT1
label_EFFECT1:	PROC
	BEGIN
	;[250] 	GOSUB reset_sound
	SRCFILE "Maze.bas",250
	CALL label_RESET_SOUND
	;[251] 	FOR A = 1 TO 4
	SRCFILE "Maze.bas",251
	MVII #1,R0
	MVO R0,var_A
T73:
	;[252]         IF A=1 THEN #C=700
	SRCFILE "Maze.bas",252
	MVI var_A,R0
	CMPI #1,R0
	BNE T74
	MVII #700,R0
	MVO R0,var_&C
T74:
	;[253]         IF A=2 THEN #C=750
	SRCFILE "Maze.bas",253
	MVI var_A,R0
	CMPI #2,R0
	BNE T75
	MVII #750,R0
	MVO R0,var_&C
T75:
	;[254]         IF A=3 THEN #C=800
	SRCFILE "Maze.bas",254
	MVI var_A,R0
	CMPI #3,R0
	BNE T76
	MVII #800,R0
	MVO R0,var_&C
T76:
	;[255]         IF A=4 THEN #C=850
	SRCFILE "Maze.bas",255
	MVI var_A,R0
	CMPI #4,R0
	BNE T77
	MVII #850,R0
	MVO R0,var_&C
T77:
	;[256]         IF A=5 THEN #C=379
	SRCFILE "Maze.bas",256
	MVI var_A,R0
	CMPI #5,R0
	BNE T78
	MVII #379,R0
	MVO R0,var_&C
T78:
	;[257]         IF A=6 THEN #C=319
	SRCFILE "Maze.bas",257
	MVI var_A,R0
	CMPI #6,R0
	BNE T79
	MVII #319,R0
	MVO R0,var_&C
T79:
	;[258]         IF A=7 THEN #C=451
	SRCFILE "Maze.bas",258
	MVI var_A,R0
	CMPI #7,R0
	BNE T80
	MVII #451,R0
	MVO R0,var_&C
T80:
	;[259]         IF A=8 THEN #C=358
	SRCFILE "Maze.bas",259
	MVI var_A,R0
	CMPI #8,R0
	BNE T81
	MVII #358,R0
	MVO R0,var_&C
T81:
	;[260]         IF A=9 THEN #C=301
	SRCFILE "Maze.bas",260
	MVI var_A,R0
	CMPI #9,R0
	BNE T82
	MVII #301,R0
	MVO R0,var_&C
T82:
	;[261]         IF A=10 THEN #C=239
	SRCFILE "Maze.bas",261
	MVI var_A,R0
	CMPI #10,R0
	BNE T83
	MVII #239,R0
	MVO R0,var_&C
T83:
	;[262] 	SOUND 0,#C,PSG_ENVELOPE_ENABLE
	SRCFILE "Maze.bas",262
	MVI var_&C,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #48,R0
	MVO R0,507
	;[263] 	SOUND 1,(#C+1)/2,PSG_ENVELOPE_ENABLE
	SRCFILE "Maze.bas",263
	MVI var_&C,R0
	INCR R0
	SLR R0,1
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #48,R0
	MVO R0,508
	;[264] 	SOUND 2,#C*2,PSG_ENVELOPE_ENABLE
	SRCFILE "Maze.bas",264
	MVI var_&C,R0
	SLL R0,1
	MVO R0,498
	SWAP R0
	MVO R0,502
	MVII #48,R0
	MVO R0,509
	;[265] 	SOUND 3,6000,PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_OFF	' Slow decay, single shot \______
	SRCFILE "Maze.bas",265
	MVII #6000,R0
	MVO R0,499
	SWAP R0
	MVO R0,503
	CLRR R0
	MVO R0,506
	;[266] 	FOR C = 1 TO 30:WAIT:NEXT C
	SRCFILE "Maze.bas",266
	MVII #1,R0
	MVO R0,var_C
T84:
	CALL _wait
	MVI var_C,R0
	INCR R0
	MVO R0,var_C
	CMPI #30,R0
	BLE T84
	;[267] 	NEXT A
	SRCFILE "Maze.bas",267
	MVI var_A,R0
	INCR R0
	MVO R0,var_A
	CMPI #4,R0
	BLE T73
	;[268] 	RETURN
	SRCFILE "Maze.bas",268
	RETURN
	;[269] 	END
	SRCFILE "Maze.bas",269
	ENDP
	;[270] 
	SRCFILE "Maze.bas",270
	;[271] effect2:	PROCEDURE
	SRCFILE "Maze.bas",271
	; EFFECT2
label_EFFECT2:	PROC
	BEGIN
	;[272] 	GOSUB reset_sound
	SRCFILE "Maze.bas",272
	CALL label_RESET_SOUND
	;[273] 	FOR A = 5 TO 5
	SRCFILE "Maze.bas",273
	MVII #5,R0
	MVO R0,var_A
T85:
	;[274]         IF A=1 THEN #C=477
	SRCFILE "Maze.bas",274
	MVI var_A,R0
	CMPI #1,R0
	BNE T86
	MVII #477,R0
	MVO R0,var_&C
T86:
	;[275]         IF A=2 THEN #C=379
	SRCFILE "Maze.bas",275
	MVI var_A,R0
	CMPI #2,R0
	BNE T87
	MVII #379,R0
	MVO R0,var_&C
T87:
	;[276]         IF A=3 THEN #C=319
	SRCFILE "Maze.bas",276
	MVI var_A,R0
	CMPI #3,R0
	BNE T88
	MVII #319,R0
	MVO R0,var_&C
T88:
	;[277]         IF A=4 THEN #C=477
	SRCFILE "Maze.bas",277
	MVI var_A,R0
	CMPI #4,R0
	BNE T89
	MVII #477,R0
	MVO R0,var_&C
T89:
	;[278]         IF A=5 THEN #C=379
	SRCFILE "Maze.bas",278
	MVI var_A,R0
	CMPI #5,R0
	BNE T90
	MVII #379,R0
	MVO R0,var_&C
T90:
	;[279]         IF A=6 THEN #C=319
	SRCFILE "Maze.bas",279
	MVI var_A,R0
	CMPI #6,R0
	BNE T91
	MVII #319,R0
	MVO R0,var_&C
T91:
	;[280]         IF A=7 THEN #C=451
	SRCFILE "Maze.bas",280
	MVI var_A,R0
	CMPI #7,R0
	BNE T92
	MVII #451,R0
	MVO R0,var_&C
T92:
	;[281]         IF A=8 THEN #C=358
	SRCFILE "Maze.bas",281
	MVI var_A,R0
	CMPI #8,R0
	BNE T93
	MVII #358,R0
	MVO R0,var_&C
T93:
	;[282]         IF A=9 THEN #C=301
	SRCFILE "Maze.bas",282
	MVI var_A,R0
	CMPI #9,R0
	BNE T94
	MVII #301,R0
	MVO R0,var_&C
T94:
	;[283]         IF A=10 THEN #C=239
	SRCFILE "Maze.bas",283
	MVI var_A,R0
	CMPI #10,R0
	BNE T95
	MVII #239,R0
	MVO R0,var_&C
T95:
	;[284] 	SOUND 0,#C,PSG_ENVELOPE_ENABLE
	SRCFILE "Maze.bas",284
	MVI var_&C,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #48,R0
	MVO R0,507
	;[285] 	SOUND 1,(#C+1)/2,PSG_ENVELOPE_ENABLE
	SRCFILE "Maze.bas",285
	MVI var_&C,R0
	INCR R0
	SLR R0,1
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #48,R0
	MVO R0,508
	;[286] 	SOUND 2,#C*2,PSG_ENVELOPE_ENABLE
	SRCFILE "Maze.bas",286
	MVI var_&C,R0
	SLL R0,1
	MVO R0,498
	SWAP R0
	MVO R0,502
	MVII #48,R0
	MVO R0,509
	;[287] 	SOUND 3,6000,PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_OFF	' Slow decay, single shot \______
	SRCFILE "Maze.bas",287
	MVII #6000,R0
	MVO R0,499
	SWAP R0
	MVO R0,503
	CLRR R0
	MVO R0,506
	;[288] 	FOR C = 1 TO 30:WAIT:NEXT C
	SRCFILE "Maze.bas",288
	MVII #1,R0
	MVO R0,var_C
T96:
	CALL _wait
	MVI var_C,R0
	INCR R0
	MVO R0,var_C
	CMPI #30,R0
	BLE T96
	;[289] 	NEXT A
	SRCFILE "Maze.bas",289
	MVI var_A,R0
	INCR R0
	MVO R0,var_A
	CMPI #5,R0
	BLE T85
	;[290] 	RETURN
	SRCFILE "Maze.bas",290
	RETURN
	;[291] 	END
	SRCFILE "Maze.bas",291
	ENDP
	;[292] 
	SRCFILE "Maze.bas",292
	;[293] effect3:	PROCEDURE
	SRCFILE "Maze.bas",293
	; EFFECT3
label_EFFECT3:	PROC
	BEGIN
	;[294] 	GOSUB reset_sound
	SRCFILE "Maze.bas",294
	CALL label_RESET_SOUND
	;[295] 	FOR A = 8 TO 9
	SRCFILE "Maze.bas",295
	MVII #8,R0
	MVO R0,var_A
T97:
	;[296]         IF A=1 THEN #C=477
	SRCFILE "Maze.bas",296
	MVI var_A,R0
	CMPI #1,R0
	BNE T98
	MVII #477,R0
	MVO R0,var_&C
T98:
	;[297]         IF A=2 THEN #C=379
	SRCFILE "Maze.bas",297
	MVI var_A,R0
	CMPI #2,R0
	BNE T99
	MVII #379,R0
	MVO R0,var_&C
T99:
	;[298]         IF A=3 THEN #C=319
	SRCFILE "Maze.bas",298
	MVI var_A,R0
	CMPI #3,R0
	BNE T100
	MVII #319,R0
	MVO R0,var_&C
T100:
	;[299]         IF A=4 THEN #C=477
	SRCFILE "Maze.bas",299
	MVI var_A,R0
	CMPI #4,R0
	BNE T101
	MVII #477,R0
	MVO R0,var_&C
T101:
	;[300]         IF A=5 THEN #C=379
	SRCFILE "Maze.bas",300
	MVI var_A,R0
	CMPI #5,R0
	BNE T102
	MVII #379,R0
	MVO R0,var_&C
T102:
	;[301]         IF A=6 THEN #C=319
	SRCFILE "Maze.bas",301
	MVI var_A,R0
	CMPI #6,R0
	BNE T103
	MVII #319,R0
	MVO R0,var_&C
T103:
	;[302]         IF A=7 THEN #C=451
	SRCFILE "Maze.bas",302
	MVI var_A,R0
	CMPI #7,R0
	BNE T104
	MVII #451,R0
	MVO R0,var_&C
T104:
	;[303]         IF A=8 THEN #C=200
	SRCFILE "Maze.bas",303
	MVI var_A,R0
	CMPI #8,R0
	BNE T105
	MVII #200,R0
	MVO R0,var_&C
T105:
	;[304]         IF A=9 THEN #C=100
	SRCFILE "Maze.bas",304
	MVI var_A,R0
	CMPI #9,R0
	BNE T106
	MVII #100,R0
	MVO R0,var_&C
T106:
	;[305]         IF A=10 THEN #C=239
	SRCFILE "Maze.bas",305
	MVI var_A,R0
	CMPI #10,R0
	BNE T107
	MVII #239,R0
	MVO R0,var_&C
T107:
	;[306] 	SOUND 0,#C,PSG_ENVELOPE_ENABLE
	SRCFILE "Maze.bas",306
	MVI var_&C,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #48,R0
	MVO R0,507
	;[307] 	SOUND 1,(#C+1)/2,PSG_ENVELOPE_ENABLE
	SRCFILE "Maze.bas",307
	MVI var_&C,R0
	INCR R0
	SLR R0,1
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #48,R0
	MVO R0,508
	;[308] 	SOUND 2,#C*2,PSG_ENVELOPE_ENABLE
	SRCFILE "Maze.bas",308
	MVI var_&C,R0
	SLL R0,1
	MVO R0,498
	SWAP R0
	MVO R0,502
	MVII #48,R0
	MVO R0,509
	;[309] 	SOUND 3,6000,PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_OFF	' Slow decay, single shot \______
	SRCFILE "Maze.bas",309
	MVII #6000,R0
	MVO R0,499
	SWAP R0
	MVO R0,503
	CLRR R0
	MVO R0,506
	;[310] 	FOR C = 1 TO 30:WAIT:NEXT C
	SRCFILE "Maze.bas",310
	MVII #1,R0
	MVO R0,var_C
T108:
	CALL _wait
	MVI var_C,R0
	INCR R0
	MVO R0,var_C
	CMPI #30,R0
	BLE T108
	;[311] 	NEXT A
	SRCFILE "Maze.bas",311
	MVI var_A,R0
	INCR R0
	MVO R0,var_A
	CMPI #9,R0
	BLE T97
	;[312] 	RETURN
	SRCFILE "Maze.bas",312
	RETURN
	;[313] 	END
	SRCFILE "Maze.bas",313
	ENDP
	;[314] 
	SRCFILE "Maze.bas",314
	;[315] 
	SRCFILE "Maze.bas",315
	;[316] tune: DATA 5
	SRCFILE "Maze.bas",316
	; TUNE
label_TUNE:		DECLE 5
	;[317] 	MUSIC G5#Y,C3#,-,M1
	SRCFILE "Maze.bas",317
	DECLE 3757,256
	;[318] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",318
	DECLE 16191,512
	;[319] 	MUSIC F5#,G3#,-,M2
	SRCFILE "Maze.bas",319
	DECLE 5547,512
	;[320] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",320
	DECLE 16191,512
	;[321] 	MUSIC E5,C3#,-,M1
	SRCFILE "Maze.bas",321
	DECLE 3753,256
	;[322] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",322
	DECLE 16191,512
	;[323] 	MUSIC D5#,G3#,-,M2
	SRCFILE "Maze.bas",323
	DECLE 5544,512
	;[324] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",324
	DECLE 16191,512
	;[325] 	MUSIC E5,C3#,-,M1
	SRCFILE "Maze.bas",325
	DECLE 3753,256
	;[326] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",326
	DECLE 16191,512
	;[327] 	MUSIC F5#,G3#,-,M2
	SRCFILE "Maze.bas",327
	DECLE 5547,512
	;[328] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",328
	DECLE 16191,512
	;[329] 	MUSIC G5#,C3#,-,M1
	SRCFILE "Maze.bas",329
	DECLE 3757,256
	;[330] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",330
	DECLE 16191,512
	;[331] 	MUSIC S,G3#,-,M2
	SRCFILE "Maze.bas",331
	DECLE 5439,512
	;[332] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",332
	DECLE 16191,512
	;[333] 	MUSIC S,C3#,-,M1
	SRCFILE "Maze.bas",333
	DECLE 3647,256
	;[334] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",334
	DECLE 16191,512
	;[335] 	MUSIC C5#,G3#,-,M2
	SRCFILE "Maze.bas",335
	DECLE 5542,512
	;[336] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",336
	DECLE 16128,512
	;[337] 	MUSIC G5#,C3#,-,M1
	SRCFILE "Maze.bas",337
	DECLE 3757,256
	;[338] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",338
	DECLE 16191,512
	;[339] 	MUSIC E5,G3#,-,M2
	SRCFILE "Maze.bas",339
	DECLE 5545,512
	;[340] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",340
	DECLE 16128,512
	;[341] 	MUSIC F5#,B2,-,M1
	SRCFILE "Maze.bas",341
	DECLE 3243,256
	;[342] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",342
	DECLE 16191,512
	;[343] 	MUSIC S,F3#,-,M2
	SRCFILE "Maze.bas",343
	DECLE 4927,512
	;[344] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",344
	DECLE 16191,512
	;[345] 	MUSIC S,B2,-,M1
	SRCFILE "Maze.bas",345
	DECLE 3135,256
	;[346] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",346
	DECLE 16191,512
	;[347] 	MUSIC -,F3#,-,M2
	SRCFILE "Maze.bas",347
	DECLE 4864,512
	;[348] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",348
	DECLE 16128,512
	;[349] 	MUSIC -,B2,-,M1
	SRCFILE "Maze.bas",349
	DECLE 3072,256
	;[350] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",350
	DECLE 16128,512
	;[351] 	MUSIC -,F3#,-,M2
	SRCFILE "Maze.bas",351
	DECLE 4864,512
	;[352] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",352
	DECLE 16128,512
	;[353] 	MUSIC -,B2,-,M1
	SRCFILE "Maze.bas",353
	DECLE 3072,256
	;[354] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",354
	DECLE 16128,512
	;[355] 	MUSIC -,F3#,-,M1
	SRCFILE "Maze.bas",355
	DECLE 4864,256
	;[356] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",356
	DECLE 16128,512
	;[357] 	MUSIC C5#,B2,-,M1
	SRCFILE "Maze.bas",357
	DECLE 3238,256
	;[358] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",358
	DECLE 16191,512
	;[359] 	MUSIC F5#,F3#,-,M1
	SRCFILE "Maze.bas",359
	DECLE 5035,256
	;[360] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",360
	DECLE 16191,512
	;[361] 	MUSIC C5#,B2,-,M1
	SRCFILE "Maze.bas",361
	DECLE 3238,256
	;[362] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",362
	DECLE 16191,512
	;[363] 	MUSIC E5,A2,-,M1
	SRCFILE "Maze.bas",363
	DECLE 2729,256
	;[364] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",364
	DECLE 16191,512
	;[365] 	MUSIC S,E3,-,M1
	SRCFILE "Maze.bas",365
	DECLE 4415,256
	;[366] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",366
	DECLE 16191,512
	;[367] 	MUSIC S,A2,-,M1
	SRCFILE "Maze.bas",367
	DECLE 2623,256
	;[368] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",368
	DECLE 16191,512
	;[369] 	MUSIC S,E3,-,M1
	SRCFILE "Maze.bas",369
	DECLE 4415,256
	;[370] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",370
	DECLE 16191,512
	;[371] 	MUSIC S,A2,-,M1
	SRCFILE "Maze.bas",371
	DECLE 2623,256
	;[372] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",372
	DECLE 16191,512
	;[373] 	MUSIC S,E3,-,M1
	SRCFILE "Maze.bas",373
	DECLE 4415,256
	;[374] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",374
	DECLE 16191,512
	;[375] 	MUSIC S,A2,-,M1
	SRCFILE "Maze.bas",375
	DECLE 2623,256
	;[376] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",376
	DECLE 16191,512
	;[377] 	MUSIC F5#,E3,-,M1
	SRCFILE "Maze.bas",377
	DECLE 4523,256
	;[378] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",378
	DECLE 16191,512
	;[379] 	MUSIC E5,A2,-,M2
	SRCFILE "Maze.bas",379
	DECLE 2729,512
	;[380] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",380
	DECLE 16191,512
	;[381] 	MUSIC D5#,E3,-,M1
	SRCFILE "Maze.bas",381
	DECLE 4520,256
	;[382] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",382
	DECLE 16191,512
	;[383] 	MUSIC S,A2,-,M2
	SRCFILE "Maze.bas",383
	DECLE 2623,512
	;[384] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",384
	DECLE 16191,512
	;[385] 	MUSIC C5,G2#,-,M1
	SRCFILE "Maze.bas",385
	DECLE 2469,256
	;[386] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",386
	DECLE 16191,512
	;[387] 	MUSIC S,D3#,-,M2
	SRCFILE "Maze.bas",387
	DECLE 4159,512
	;[388] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",388
	DECLE 16191,512
	;[389] 	MUSIC S,G2#,-,M1
	SRCFILE "Maze.bas",389
	DECLE 2367,256
	;[390] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",390
	DECLE 16191,512
	;[391] 	MUSIC S,D3#,-,M2
	SRCFILE "Maze.bas",391
	DECLE 4159,512
	;[392] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",392
	DECLE 16191,512
	;[393] 	MUSIC S,G2#,-,M1
	SRCFILE "Maze.bas",393
	DECLE 2367,256
	;[394] 	MUSIC S,S,-,M2
	SRCFILE "Maze.bas",394
	DECLE 16191,512
	;[395] 	MUSIC -,D3#,-,M2
	SRCFILE "Maze.bas",395
	DECLE 4096,512
	;[396] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",396
	DECLE 16128,512
	;[397] 	MUSIC -,G2#,-,M1
	SRCFILE "Maze.bas",397
	DECLE 2304,256
	;[398] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",398
	DECLE 16128,512
	;[399] 	MUSIC -,D3#,-,M2
	SRCFILE "Maze.bas",399
	DECLE 4096,512
	;[400] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",400
	DECLE 16128,512
	;[401] 	MUSIC -,G2#,-,M1
	SRCFILE "Maze.bas",401
	DECLE 2304,256
	;[402] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",402
	DECLE 16128,512
	;[403] 	MUSIC -,D3#,-,M1
	SRCFILE "Maze.bas",403
	DECLE 4096,256
	;[404] 	MUSIC -,S,-,M3
	SRCFILE "Maze.bas",404
	DECLE 16128,768
	;[405] 	MUSIC -,G2#,-,M1
	SRCFILE "Maze.bas",405
	DECLE 2304,256
	;[406] 	MUSIC -,S,-,M2
	SRCFILE "Maze.bas",406
	DECLE 16128,512
	;[407] 	MUSIC -,D3#,-,M1
	SRCFILE "Maze.bas",407
	DECLE 4096,256
	;[408] 	MUSIC -,S,-,M3
	SRCFILE "Maze.bas",408
	DECLE 16128,768
	;[409] 	MUSIC -,G2#,-,M1
	SRCFILE "Maze.bas",409
	DECLE 2304,256
	;[410] 	MUSIC -,S,-,M1
	SRCFILE "Maze.bas",410
	DECLE 16128,256
	;[411] 	MUSIC -,D3#,-,M1
	SRCFILE "Maze.bas",411
	DECLE 4096,256
	;[412] 	MUSIC -,S,-,M1
	SRCFILE "Maze.bas",412
	DECLE 16128,256
	;[413] 	MUSIC REPEAT
	SRCFILE "Maze.bas",413
	DECLE 0,64768
	;[414] 	
	SRCFILE "Maze.bas",414
	;[415] room0:
	SRCFILE "Maze.bas",415
	; ROOM0
label_ROOM0:	;[416] 	DATA &1111111111111111
	SRCFILE "Maze.bas",416
	DECLE 65535
	;[417] 	DATA &1000000000000001
	SRCFILE "Maze.bas",417
	DECLE 32769
	;[418] 	DATA &1000000000000001
	SRCFILE "Maze.bas",418
	DECLE 32769
	;[419] 	DATA &1000010000100001
	SRCFILE "Maze.bas",419
	DECLE 33825
	;[420] 	DATA &1000010000100001
	SRCFILE "Maze.bas",420
	DECLE 33825
	;[421] 	DATA &1000010000100001
	SRCFILE "Maze.bas",421
	DECLE 33825
	;[422] 	DATA &1000010000100001
	SRCFILE "Maze.bas",422
	DECLE 33825
	;[423] 	DATA &1000010000100001
	SRCFILE "Maze.bas",423
	DECLE 33825
	;[424] 	DATA &1000010000100001
	SRCFILE "Maze.bas",424
	DECLE 33825
	;[425] 	DATA &1000000000000001
	SRCFILE "Maze.bas",425
	DECLE 32769
	;[426] 	DATA &1000000000000001
	SRCFILE "Maze.bas",426
	DECLE 32769
	;[427] 	DATA &1111110000111111
	SRCFILE "Maze.bas",427
	DECLE 64575
	;[428] 
	SRCFILE "Maze.bas",428
	;[429] 
	SRCFILE "Maze.bas",429
	;[430] room1:
	SRCFILE "Maze.bas",430
	; ROOM1
label_ROOM1:	;[431] 	DATA &1111111111111111
	SRCFILE "Maze.bas",431
	DECLE 65535
	;[432] 	DATA &1000000000000001
	SRCFILE "Maze.bas",432
	DECLE 32769
	;[433] 	DATA &1000000000000001
	SRCFILE "Maze.bas",433
	DECLE 32769
	;[434] 	DATA &1000011111111101
	SRCFILE "Maze.bas",434
	DECLE 34813
	;[435] 	DATA &1000010000100101
	SRCFILE "Maze.bas",435
	DECLE 33829
	;[436] 	DATA &1010000000100111
	SRCFILE "Maze.bas",436
	DECLE 40999
	;[437] 	DATA &1010010000100000
	SRCFILE "Maze.bas",437
	DECLE 42016
	;[438] 	DATA &1010010000100001
	SRCFILE "Maze.bas",438
	DECLE 42017
	;[439] 	DATA &1010011111100001
	SRCFILE "Maze.bas",439
	DECLE 42977
	;[440] 	DATA &1110000000000001
	SRCFILE "Maze.bas",440
	DECLE 57345
	;[441] 	DATA &1000000000000001
	SRCFILE "Maze.bas",441
	DECLE 32769
	;[442] 	DATA &1111111111111111
	SRCFILE "Maze.bas",442
	DECLE 65535
	;[443] 
	SRCFILE "Maze.bas",443
	;[444] room2:
	SRCFILE "Maze.bas",444
	; ROOM2
label_ROOM2:	;[445] 	DATA &1111111111111111
	SRCFILE "Maze.bas",445
	DECLE 65535
	;[446] 	DATA &1000000000000001
	SRCFILE "Maze.bas",446
	DECLE 32769
	;[447] 	DATA &1000011111100001
	SRCFILE "Maze.bas",447
	DECLE 34785
	;[448] 	DATA &1010010000100001
	SRCFILE "Maze.bas",448
	DECLE 42017
	;[449] 	DATA &1010010000111111
	SRCFILE "Maze.bas",449
	DECLE 42047
	;[450] 	DATA &1010010000100000
	SRCFILE "Maze.bas",450
	DECLE 42016
	;[451] 	DATA &1011111000100000
	SRCFILE "Maze.bas",451
	DECLE 48672
	;[452] 	DATA &1010000000100111
	SRCFILE "Maze.bas",452
	DECLE 40999
	;[453] 	DATA &1000001000100001
	SRCFILE "Maze.bas",453
	DECLE 33313
	;[454] 	DATA &1000001111100001
	SRCFILE "Maze.bas",454
	DECLE 33761
	;[455] 	DATA &1000000000000001
	SRCFILE "Maze.bas",455
	DECLE 32769
	;[456] 	DATA &1111111111111111
	SRCFILE "Maze.bas",456
	DECLE 65535
	;[457] 
	SRCFILE "Maze.bas",457
	;[458] room3:
	SRCFILE "Maze.bas",458
	; ROOM3
label_ROOM3:	;[459]     DATA &1111111111111111
	SRCFILE "Maze.bas",459
	DECLE 65535
	;[460]     DATA &1000000000000001
	SRCFILE "Maze.bas",460
	DECLE 32769
	;[461]     DATA &1000000010000101
	SRCFILE "Maze.bas",461
	DECLE 32901
	;[462]     DATA &1000000010000101
	SRCFILE "Maze.bas",462
	DECLE 32901
	;[463]     DATA &1011111011111101
	SRCFILE "Maze.bas",463
	DECLE 48893
	;[464]     DATA &1000000011111101
	SRCFILE "Maze.bas",464
	DECLE 33021
	;[465]     DATA &1001001000000101
	SRCFILE "Maze.bas",465
	DECLE 37381
	;[466]     DATA &1001001000000101
	SRCFILE "Maze.bas",466
	DECLE 37381
	;[467]     DATA &1001001111110101
	SRCFILE "Maze.bas",467
	DECLE 37877
	;[468]     DATA &1111111111110101
	SRCFILE "Maze.bas",468
	DECLE 65525
	;[469]     DATA &0000000000000101
	SRCFILE "Maze.bas",469
	DECLE 5
	;[470]     DATA &1111111111111111
	SRCFILE "Maze.bas",470
	DECLE 65535
	;[471] 
	SRCFILE "Maze.bas",471
	;[472] room4:
	SRCFILE "Maze.bas",472
	; ROOM4
label_ROOM4:	;[473]     DATA &1111111111111111
	SRCFILE "Maze.bas",473
	DECLE 65535
	;[474]     DATA &1000000000000001
	SRCFILE "Maze.bas",474
	DECLE 32769
	;[475]     DATA &1000000000000001
	SRCFILE "Maze.bas",475
	DECLE 32769
	;[476]     DATA &1000000000000001
	SRCFILE "Maze.bas",476
	DECLE 32769
	;[477]     DATA &1111110111111001
	SRCFILE "Maze.bas",477
	DECLE 65017
	;[478]     DATA &1000000000001001
	SRCFILE "Maze.bas",478
	DECLE 32777
	;[479]     DATA &1000111100101001
	SRCFILE "Maze.bas",479
	DECLE 36649
	;[480]     DATA &1000111100101001
	SRCFILE "Maze.bas",480
	DECLE 36649
	;[481]     DATA &1000100100100001
	SRCFILE "Maze.bas",481
	DECLE 35105
	;[482]     DATA &1000000101111111
	SRCFILE "Maze.bas",482
	DECLE 33151
	;[483]     DATA &1000000000000000
	SRCFILE "Maze.bas",483
	DECLE 32768
	;[484]     DATA &1111111111111111
	SRCFILE "Maze.bas",484
	DECLE 65535
	;[485] 
	SRCFILE "Maze.bas",485
	;[486] 	'
	SRCFILE "Maze.bas",486
	;[487] 	' Bitmaps used in the game
	SRCFILE "Maze.bas",487
	;[488] 	'
	SRCFILE "Maze.bas",488
	;[489] drawings:
	SRCFILE "Maze.bas",489
	; DRAWINGS
label_DRAWINGS:	;[490] 	BITMAP "#..##..#"
	SRCFILE "Maze.bas",490
	;[491] 	BITMAP "########"
	SRCFILE "Maze.bas",491
	DECLE 65433
	;[492] 	BITMAP ".#.##.#."
	SRCFILE "Maze.bas",492
	;[493] 	BITMAP ".######."
	SRCFILE "Maze.bas",493
	DECLE 32346
	;[494] 	BITMAP "..####.."
	SRCFILE "Maze.bas",494
	;[495] 	BITMAP "..#..#.."
	SRCFILE "Maze.bas",495
	DECLE 9276
	;[496] 	BITMAP "..#..#.."
	SRCFILE "Maze.bas",496
	;[497] 	BITMAP ".##..##."
	SRCFILE "Maze.bas",497
	DECLE 26148
	;[498] 
	SRCFILE "Maze.bas",498
	;[499] 	BITMAP "...##..."
	SRCFILE "Maze.bas",499
	;[500] 	BITMAP "...##..."
	SRCFILE "Maze.bas",500
	DECLE 6168
	;[501] 	BITMAP "..####.."
	SRCFILE "Maze.bas",501
	;[502] 	BITMAP "..#..#.."
	SRCFILE "Maze.bas",502
	DECLE 9276
	;[503] 	BITMAP "..####.."
	SRCFILE "Maze.bas",503
	;[504] 	BITMAP "..####.."
	SRCFILE "Maze.bas",504
	DECLE 15420
	;[505] 	BITMAP ".######."
	SRCFILE "Maze.bas",505
	;[506] 	BITMAP "##.##.##"
	SRCFILE "Maze.bas",506
	DECLE 56190
	;[507] 
	SRCFILE "Maze.bas",507
	;[508] 	BITMAP "...##..."
	SRCFILE "Maze.bas",508
	;[509] 	BITMAP "...##..."
	SRCFILE "Maze.bas",509
	DECLE 6168
	;[510] 	BITMAP ".######."
	SRCFILE "Maze.bas",510
	;[511] 	BITMAP "...##..."
	SRCFILE "Maze.bas",511
	DECLE 6270
	;[512] 	BITMAP "...##..."
	SRCFILE "Maze.bas",512
	;[513] 	BITMAP "..####.."
	SRCFILE "Maze.bas",513
	DECLE 15384
	;[514] 	BITMAP "..#..#.."
	SRCFILE "Maze.bas",514
	;[515] 	BITMAP ".##..##."
	SRCFILE "Maze.bas",515
	DECLE 26148
	;[516] 
	SRCFILE "Maze.bas",516
	;[517] 	BITMAP ".##....."
	SRCFILE "Maze.bas",517
	;[518] 	BITMAP "###....."
	SRCFILE "Maze.bas",518
	DECLE 57440
	;[519] 	BITMAP ".##....."
	SRCFILE "Maze.bas",519
	;[520] 	BITMAP ".#######"
	SRCFILE "Maze.bas",520
	DECLE 32608
	;[521] 	BITMAP ".######."
	SRCFILE "Maze.bas",521
	;[522] 	BITMAP ".##..##."
	SRCFILE "Maze.bas",522
	DECLE 26238
	;[523] 	BITMAP ".##..##."
	SRCFILE "Maze.bas",523
	;[524] 	BITMAP "###.###."
	SRCFILE "Maze.bas",524
	DECLE 61030
	;ENDFILE
	SRCFILE "",0
intybasic_music:	equ 1	; Forces to include music library
	;
	; Epilogue for IntyBASIC programs
	; by Oscar Toledo G.  http://nanochess.org/
	;
	; Revision: Jan/30/2014. Moved GRAM code below MOB updates.
	;                        Added comments.
	; Revision: Feb/26/2014. Optimized access to collision registers
	;                        per DZ-Jay suggestion. Added scrolling
	;                        routines with optimization per intvnut
	;                        suggestion. Added border/mask support.
	; Revision: Apr/02/2014. Added support to set MODE (color stack
	;                        or foreground/background), added support
	;                        for SCREEN statement.
	; Revision: Aug/19/2014. Solved bug in bottom scroll, moved an
	;                        extra unneeded line.
	; Revision: Aug/26/2014. Integrated music player and NTSC/PAL
	;                        detection.
	; Revision: Oct/24/2014. Adjust in some comments.
	; Revision: Nov/13/2014. Integrated Joseph Zbiciak's routines
	;                        for printing numbers.
	; Revision: Nov/17/2014. Redesigned MODE support to use a single
	;                        variable.
	; Revision: Nov/21/2014. Added Intellivoice support routines made
	;                        by Joseph Zbiciak.
	; Revision: Dec/11/2014. Optimized keypad decode routines.
	; Revision: Jan/25/2015. Added marker for insertion of ON FRAME GOSUB
	; Revision: Feb/17/2015. Allows to deactivate music player (PLAY NONE)
	; Revision: Apr/21/2015. Accelerates common case of keypad not pressed.
	;                        Added ECS ROM disable code.
	; Revision: Apr/22/2015. Added Joseph Zbiciak accelerated multiplication
	;                        routines.
	; Revision: Jun/04/2015. Optimized play_music (per GroovyBee suggestion)
	; Revision: Jul/25/2015. Added infinite loop at start to avoid crashing
	;                        with empty programs. Solved bug where _color
	;                        didn't started with white.
	; Revision: Aug/20/2015. Moved ECS mapper disable code so nothing gets
	;                        after it (GroovyBee 42K sample code)
	; Revision: Aug/21/2015. Added Joseph Zbiciak routines for JLP Flash
	;                        handling.
	; Revision: Aug/31/2015. Added CPYBLK2 for SCREEN fifth argument.
	; Revision: Sep/01/2015. Defined labels Q1 and Q2 as alias.
	; Revision: Jan/22/2016. Music player allows not to use noise channel
	;                        for drums. Allows setting music volume.
	; Revision: Jan/23/2016. Added jump inside of music (for MUSIC JUMP)
	; Revision: May/03/2016. Preserves current mode in bit 0 of _mode_select
	; Revision: Oct/21/2016. Added C7 in notes table, it was missing. (thanks
	;                        mmarrero)
	; Revision: Jan/09/2018. Initializes scroll offset registers (useful when
	;                        starting from $4800). Uses slightly less space.
	; Revision: Feb/05/2018. Added IV_HUSH.
	; Revision: Mar/01/2018. Added support for music tracker over ECS.
	; Revision: Sep/25/2018. Solved bug in mixer for ECS drums.
	; Revision: Oct/30/2018. Small optimization in music player.
	; Revision: Jan/09/2019. Solved bug where it would play always like
	;                        PLAY SIMPLE NO DRUMS.
	; Revision: May/18/2019. Solved bug where drums failed in ECS side.
	;

	;
	; Avoids empty programs to crash
	; 
stuck:	B stuck

	;
	; Copy screen helper for SCREEN wide statement
	;

CPYBLK2:	PROC
	MOVR R0,R3		; Offset
	MOVR R5,R2
	PULR R0
	PULR R1
	PULR R5
	PULR R4
	PSHR R2
	SUBR R1,R3

@@1:	PSHR R3
	MOVR R1,R3		; Init line copy
@@2:	MVI@ R4,R2		; Copy line
	MVO@ R2,R5
	DECR R3
	BNE @@2
	PULR R3		 ; Add offset to start in next line
	ADDR R3,R4
	SUBR R1,R5
	ADDI #20,R5
	DECR R0		 ; Count lines
	BNE @@1

	RETURN
	ENDP

	;
	; Copy screen helper for SCREEN statement
	;
CPYBLK:	PROC
	BEGIN
	MOVR R3,R4
	MOVR R2,R5

@@1:	MOVR R1,R3	      ; Init line copy
@@2:	MVI@ R4,R2	      ; Copy line
	MVO@ R2,R5
	DECR R3
	BNE @@2
	MVII #20,R3	     ; Add offset to start in next line
	SUBR R1,R3
	ADDR R3,R4
	ADDR R3,R5
	DECR R0		 ; Count lines
	BNE @@1
	RETURN
	ENDP

	;
	; Wait for interruption
	;
_wait:  PROC

    IF DEFINED intybasic_keypad
	MVI $01FF,R0
	COMR R0
	ANDI #$FF,R0
	CMP _cnt1_p0,R0
	BNE @@2
	CMP _cnt1_p1,R0
	BNE @@2
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@4
	MVII #_keypad_table,R4
    REPEAT 6
	CMP@ R4,R0
	BEQ @@4
	CMP@ R4,R0
	BEQ @@4
    ENDR
	INCR R4
@@4:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt1_key

@@2:    MVI _cnt1_p1,R1
	MVO R1,_cnt1_p0
	MVO R0,_cnt1_p1

	MVI $01FE,R0
	COMR R0
	ANDI #$FF,R0
	CMP _cnt2_p0,R0
	BNE @@5
	CMP _cnt2_p1,R0
	BNE @@5
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@7
	MVII #_keypad_table,R4
    REPEAT 6
	CMP@ R4,R0
	BEQ @@7
	CMP@ R4,R0
	BEQ @@7
    ENDR

	INCR R4
@@7:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt2_key

@@5:    MVI _cnt2_p1,R1
	MVO R1,_cnt2_p0
	MVO R0,_cnt2_p1
    ENDI

	CLRR    R0
	MVO     R0,_int	 ; Clears waiting flag
@@1:	CMP     _int,  R0       ; Waits for change
	BEQ     @@1
	JR      R5	      ; Returns
	ENDP

	;
	; Keypad table
	;
_keypad_table:	  PROC
	DECLE $48,$81,$41,$21,$82,$42,$22,$84,$44,$24,$88,$28
	ENDP

_set_isr:	PROC
	MVI@ R5,R0
	MVO R0,ISRVEC
	SWAP R0
	MVO R0,ISRVEC+1
	JR R5
	ENDP

	;
	; Interruption routine
	;
_int_vector:     PROC

    IF DEFINED intybasic_stack
	CMPI #$308,R6
	BNC @@vs
	MVO R0,$20	; Enables display
	MVI $21,R0	; Activates Color Stack mode
	CLRR R0
	MVO R0,$28
	MVO R0,$29
	MVO R0,$2A
	MVO R0,$2B
	MVII #@@vs1,R4
	MVII #$200,R5
	MVII #20,R1
@@vs2:	MVI@ R4,R0
	MVO@ R0,R5
	DECR R1
	BNE @@vs2
	RETURN

	; Stack Overflow message
@@vs1:	DECLE 0,0,0,$33*8+7,$54*8+7,$41*8+7,$43*8+7,$4B*8+7,$00*8+7
	DECLE $4F*8+7,$56*8+7,$45*8+7,$52*8+7,$46*8+7,$4C*8+7
	DECLE $4F*8+7,$57*8+7,0,0,0

@@vs:
    ENDI

	MVII #1,R1
	MVO R1,_int	; Indicates interrupt happened.

	MVI _mode_select,R0
	SARC R0,2
	BNE @@ds
	MVO R0,$20	; Enables display
@@ds:	BNC @@vi14
	MVO R0,$21	; Foreground/background mode
	BNOV @@vi0
	B @@vi15

@@vi14:	MVI $21,R0	; Color stack mode
	BNOV @@vi0
	CLRR R1
	MVI _color,R0
	MVO R0,$28
	SWAP R0
	MVO R0,$29
	SLR R0,2
	SLR R0,2
	MVO R0,$2A
	SWAP R0
	MVO R0,$2B
@@vi15:
	MVO R1,_mode_select
	MVII #7,R0
	MVO R0,_color	   ; Default color for PRINT "string"
@@vi0:

	BEGIN

	MVI _border_color,R0
	MVO     R0,     $2C     ; Border color
	MVI _border_mask,R0
	MVO     R0,     $32     ; Border mask
	;
	; Save collision registers for further use and clear them
	;
	MVII #$18,R4
	MVII #_col0,R5
	MVI@ R4,R0
	MVO@ R0,R5  ; _col0
	MVI@ R4,R0
	MVO@ R0,R5  ; _col1
	MVI@ R4,R0
	MVO@ R0,R5  ; _col2
	MVI@ R4,R0
	MVO@ R0,R5  ; _col3
	MVI@ R4,R0
	MVO@ R0,R5  ; _col4
	MVI@ R4,R0
	MVO@ R0,R5  ; _col5
	MVI@ R4,R0
	MVO@ R0,R5  ; _col6
	MVI@ R4,R0
	MVO@ R0,R5  ; _col7
	
    IF DEFINED intybasic_scroll

	;
	; Scrolling things
	;
	MVI _scroll_x,R0
	MVO R0,$30
	MVI _scroll_y,R0
	MVO R0,$31
    ENDI

	;
	; Updates sprites (MOBs)
	;
	MOVR R5,R4	; MVII #_mobs,R4
	CLRR R5		; X-coordinates
    REPEAT 8
	MVI@ R4,R0
	MVO@ R0,R5
	MVI@ R4,R0
	MVO@ R0,R5
	MVI@ R4,R0
	MVO@ R0,R5
    ENDR
	CLRR R0		; Erase collision bits (R5 = $18)
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5

    IF DEFINED intybasic_music
     	MVI _ntsc,R0
	RRC R0,1	 ; PAL?
	BNC @@vo97      ; Yes, always emit sound
	MVI _music_frame,R0
	INCR R0
	CMPI #6,R0
	BNE @@vo14
	CLRR R0
@@vo14:	MVO R0,_music_frame
	BEQ @@vo15
@@vo97:	CALL _emit_sound
    IF DEFINED intybasic_music_ecs
	CALL _emit_sound_ecs
    ENDI
@@vo15:
    ENDI

	;
	; Detect GRAM definition
	;
	MVI _gram_bitmap,R4
	TSTR R4
	BEQ @@vi1
	MVI _gram_target,R1
	SLL R1,2
	SLL R1,1
	ADDI #$3800,R1
	MOVR R1,R5
	MVI _gram_total,R0
@@vi3:
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	DECR R0
	BNE @@vi3
	MVO R0,_gram_bitmap
@@vi1:
	MVI _gram2_bitmap,R4
	TSTR R4
	BEQ @@vii1
	MVI _gram2_target,R1
	SLL R1,2
	SLL R1,1
	ADDI #$3800,R1
	MOVR R1,R5
	MVI _gram2_total,R0
@@vii3:
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	DECR R0
	BNE @@vii3
	MVO R0,_gram2_bitmap
@@vii1:

    IF DEFINED intybasic_scroll
	;
	; Frame scroll support
	;
	MVI _scroll_d,R0
	TSTR R0
	BEQ @@vi4
	CLRR R1
	MVO R1,_scroll_d
	DECR R0     ; Left
	BEQ @@vi5
	DECR R0     ; Right
	BEQ @@vi6
	DECR R0     ; Top
	BEQ @@vi7
	DECR R0     ; Bottom
	BEQ @@vi8
	B @@vi4

@@vi5:  MVII #$0200,R4
	MOVR R4,R5
	INCR R5
	MVII #12,R1
@@vi12: MVI@ R4,R2
	MVI@ R4,R3
	REPEAT 8
	MVO@ R2,R5
	MVI@ R4,R2
	MVO@ R3,R5
	MVI@ R4,R3
	ENDR
	MVO@ R2,R5
	MVI@ R4,R2
	MVO@ R3,R5
	MVO@ R2,R5
	INCR R4
	INCR R5
	DECR R1
	BNE @@vi12
	B @@vi4

@@vi6:  MVII #$0201,R4
	MVII #$0200,R5
	MVII #12,R1
@@vi11:
	REPEAT 19
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	INCR R4
	INCR R5
	DECR R1
	BNE @@vi11
	B @@vi4
    
	;
	; Complex routine to be ahead of STIC display
	; Moves first the top 6 lines, saves intermediate line
	; Then moves the bottom 6 lines and restores intermediate line
	;
@@vi7:  MVII #$0264,R4
	MVII #5,R1
	MVII #_scroll_buffer,R5
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	SUBI #40,R4
	MOVR R4,R5
	ADDI #20,R5
@@vi10:
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	SUBI #40,R4
	SUBI #40,R5
	DECR R1
	BNE @@vi10
	MVII #$02C8,R4
	MVII #$02DC,R5
	MVII #5,R1
@@vi13:
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	SUBI #40,R4
	SUBI #40,R5
	DECR R1
	BNE @@vi13
	MVII #_scroll_buffer,R4
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	B @@vi4

@@vi8:  MVII #$0214,R4
	MVII #$0200,R5
	MVII #$DC/4,R1
@@vi9:  
	REPEAT 4
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	DECR R1
	BNE @@vi9
	B @@vi4

@@vi4:
    ENDI

    IF DEFINED intybasic_voice
	;
	; Intellivoice support
	;
	CALL IV_ISR
    ENDI

	;
	; Random number generator
	;
	CALL _next_random

    IF DEFINED intybasic_music
	; Generate sound for next frame
       	MVI _ntsc,R0
	RRC R0,1	 ; PAL?
	BNC @@vo98      ; Yes, always generate sound
	MVI _music_frame,R0
	TSTR R0
	BEQ @@vo16
@@vo98: CALL _generate_music
@@vo16:
    ENDI

	; Increase frame number
	MVI _frame,R0
	INCR R0
	MVO R0,_frame

	; This mark is for ON FRAME GOSUB support
	CALL label_FRAME_UPDATE

	RETURN
	ENDP

	;
	; Generates the next random number
	;
_next_random:	PROC

MACRO _ROR
	RRC R0,1
	MOVR R0,R2
	SLR R2,2
	SLR R2,2
	ANDI #$0800,R2
	SLR R2,2
	SLR R2,2
	ANDI #$007F,R0
	XORR R2,R0
ENDM
	MVI _rand,R0
	SETC
	_ROR
	XOR _frame,R0
	_ROR
	XOR _rand,R0
	_ROR
	XORI #9,R0
	MVO R0,_rand
	JR R5
	ENDP

    IF DEFINED intybasic_music

	;
	; Music player, comes from my game Princess Quest for Intellivision
	; so it's a practical tracker used in a real game ;) and with enough
	; features.
	;

	; NTSC frequency for notes (based on 3.579545 mhz)
ntsc_note_table:    PROC
	; Silence - 0
	DECLE 0
	; Octave 2 - 1
	DECLE 1721,1621,1532,1434,1364,1286,1216,1141,1076,1017,956,909
	; Octave 3 - 13
	DECLE 854,805,761,717,678,639,605,571,538,508,480,453
	; Octave 4 - 25
	DECLE 427,404,380,360,339,321,302,285,270,254,240,226
	; Octave 5 - 37
	DECLE 214,202,191,180,170,160,151,143,135,127,120,113
	; Octave 6 - 49
	DECLE 107,101,95,90,85,80,76,71,67,64,60,57
	; Octave 7 - 61
	DECLE 54
	; Space for two notes more
	ENDP

	; PAL frequency for notes (based on 4 mhz)
pal_note_table:    PROC
	; Silence - 0
	DECLE 0
	; Octava 2 - 1
	DECLE 1923,1812,1712,1603,1524,1437,1359,1276,1202,1136,1068,1016
	; Octava 3 - 13
	DECLE 954,899,850,801,758,714,676,638,601,568,536,506
	; Octava 4 - 25
	DECLE 477,451,425,402,379,358,338,319,301,284,268,253
	; Octava 5 - 37
	DECLE 239,226,213,201,190,179,169,159,150,142,134,127
	; Octava 6 - 49
	DECLE 120,113,106,100,95,89,84,80,75,71,67,63
	; Octava 7 - 61
	DECLE 60
	; Space for two notes more
	ENDP
    ENDI

	;
	; Music tracker init
	;
_init_music:	PROC
    IF DEFINED intybasic_music
	MVI _ntsc,R0
	RRC R0,1
	MVII #ntsc_note_table,R0
	BC @@0
	MVII #pal_note_table,R0
@@0:	MVO R0,_music_table
	MVII #$38,R0	; $B8 blocks controllers o.O!
	MVO R0,_music_mix
    IF DEFINED intybasic_music_ecs
	MVO R0,_music2_mix
    ENDI
	CLRR R0
    ELSE
	JR R5		; Tracker disabled (no PLAY statement used)
    ENDI
	ENDP

    IF DEFINED intybasic_music
	;
	; Start music
	; R0 = Pointer to music
	;
_play_music:	PROC
	MVII #1,R1
	MOVR R1,R3
	MOVR R0,R2
	BEQ @@1
	MVI@ R2,R3
	INCR R2
@@1:	MVO R2,_music_p
	MVO R2,_music_start
	SWAP R2
	MVO R2,_music_start+1
	MVO R3,_music_t
	MVO R1,_music_tc
	JR R5

	ENDP

	;
	; Generate music
	;
_generate_music:	PROC
	BEGIN
	MVI _music_mix,R0
	ANDI #$C0,R0
	XORI #$38,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_ecs
	MVI _music2_mix,R0
	ANDI #$C0,R0
	XORI #$38,R0
	MVO R0,_music2_mix
    ENDI
	CLRR R1			; Turn off volume for the three sound channels
	MVO R1,_music_vol1
	MVO R1,_music_vol2
	MVI _music_tc,R3
	MVO R1,_music_vol3
    IF DEFINED intybasic_music_ecs
	MVO R1,_music2_vol1
	NOP
	MVO R1,_music2_vol2
	MVO R1,_music2_vol3
    ENDI
	DECR R3
	MVO R3,_music_tc
	BNE @@6
	; R3 is zero from here up to @@6
	MVI _music_p,R4
@@15:	TSTR R4		; Silence?
	BEQ @@43	; Keep quiet
@@41:	MVI@ R4,R0
	MVI@ R4,R1
	MVI _music_t,R2
	CMPI #$FA00,R1	; Volume?
	BNC @@42
    IF DEFINED intybasic_music_volume
	BEQ @@40
    ENDI
	CMPI #$FF00,R1	; Speed?
	BEQ @@39
	CMPI #$FB00,R1	; Return?
	BEQ @@38
	CMPI #$FC00,R1	; Gosub?
	BEQ @@37
	CMPI #$FE00,R1	; The end?
	BEQ @@36       ; Keep quiet
;	CMPI #$FD00,R1	; Repeat?
;	BNE @@42
	MVI _music_start+1,R0
	SWAP R0
	ADD _music_start,R0
	MOVR R0,R4
	B @@15

    IF DEFINED intybasic_music_volume
@@40:	
	MVO R0,_music_vol
	B @@41
    ENDI

@@39:	MVO R0,_music_t
	MOVR R0,R2
	B @@41

@@38:	MVI _music_gosub,R4
	B @@15

@@37:	MVO R4,_music_gosub
@@36:	MOVR R0,R4	; Jump, zero will make it quiet
	B @@15

@@43:	MVII #1,R0
	MVO R0,_music_tc
	B @@0
	
@@42: 	MVO R2,_music_tc    ; Restart note time
     	MVO R4,_music_p
     	
	MOVR R0,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@1
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n1	; Note
	MVO R3,_music_s1	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i1	; Instrument
	
@@1:	SWAP R0
	ANDI #$FF,R0
	CMPI #$3F,R0	; Sustain note?
	BEQ @@2
	MOVR R0,R4
	ANDI #$3F,R4
	MVO R4,_music_n2	; Note
	MVO R3,_music_s2	; Waveform
	ANDI #$C0,R0
	MVO R0,_music_i2	; Instrument
	
@@2:	MOVR R1,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@3
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n3	; Note
	MVO R3,_music_s3	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i3	; Instrument
	
@@3:	SWAP R1
	MVO R1,_music_n4
	MVO R3,_music_s4
	
    IF DEFINED intybasic_music_ecs
	MVI _music_p,R4
	MVI@ R4,R0
	MVI@ R4,R1
	MVO R4,_music_p

	MOVR R0,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@33
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n5	; Note
	MVO R3,_music_s5	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i5	; Instrument
	
@@33:	SWAP R0
	ANDI #$FF,R0
	CMPI #$3F,R0	; Sustain note?
	BEQ @@34
	MOVR R0,R4
	ANDI #$3F,R4
	MVO R4,_music_n6	; Note
	MVO R3,_music_s6	; Waveform
	ANDI #$C0,R0
	MVO R0,_music_i6	; Instrument
	
@@34:	MOVR R1,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@35
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n7	; Note
	MVO R3,_music_s7	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i7	; Instrument
	
@@35:	MOVR R1,R2
	SWAP R2
	MVO R2,_music_n8
	MVO R3,_music_s8
	
    ENDI

	;
	; Construct main voice
	;
@@6:	MVI _music_n1,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@7		; No, jump
	MVI _music_s1,R1
	MVI _music_i1,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq10	; Note in voice A
	SWAP R3
	MVO R3,_music_freq11
	MVO R1,_music_vol1
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@20
	SUBI #$08,R0
@@20:	MVO R0,_music_s1

@@7:	MVI _music_n2,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@8		; No, jump
	MVI _music_s2,R1
	MVI _music_i2,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq20	; Note in voice B
	SWAP R3
	MVO R3,_music_freq21
	MVO R1,_music_vol2
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@21
	SUBI #$08,R0
@@21:	MVO R0,_music_s2

@@8:	MVI _music_n3,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@9		; No, jump
	MVI _music_s3,R1
	MVI _music_i3,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq30	; Note in voice C
	SWAP R3
	MVO R3,_music_freq31
	MVO R1,_music_vol3
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@22
	SUBI #$08,R0
@@22:	MVO R0,_music_s3

@@9:	MVI _music_n4,R0	; Read drum
	DECR R0		; There is drum?
	BMI @@4		; No, jump
	MVI _music_s4,R1
	       		; 1 - Strong
	BNE @@5
	CMPI #3,R1
	BGE @@12
@@10:	MVII #5,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@5:	DECR R0		;2 - Short
	BNE @@11
	TSTR R1
	BNE @@12
	MVII #8,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@11:	;DECR R0	; 3 - Rolling
	;BNE @@12
	CMPI #2,R1
	BLT @@10
	MVI _music_t,R0
	SLR R0,1
	CMPR R0,R1
	BLT @@12
	ADDI #2,R0
	CMPR R0,R1
	BLT @@10
	; Increase time for drum waveform
@@12:   INCR R1
	MVO R1,_music_s4

@@4:
    IF DEFINED intybasic_music_ecs
	;
	; Construct main voice
	;
	MVI _music_n5,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@23	; No, jump
	MVI _music_s5,R1
	MVI _music_i5,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music2_freq10	; Note in voice A
	SWAP R3
	MVO R3,_music2_freq11
	MVO R1,_music2_vol1
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@24
	SUBI #$08,R0
@@24:	MVO R0,_music_s5

@@23:	MVI _music_n6,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@25		; No, jump
	MVI _music_s6,R1
	MVI _music_i6,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music2_freq20	; Note in voice B
	SWAP R3
	MVO R3,_music2_freq21
	MVO R1,_music2_vol2
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@26
	SUBI #$08,R0
@@26:	MVO R0,_music_s6

@@25:	MVI _music_n7,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@27		; No, jump
	MVI _music_s7,R1
	MVI _music_i7,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music2_freq30	; Note in voice C
	SWAP R3
	MVO R3,_music2_freq31
	MVO R1,_music2_vol3
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@28
	SUBI #$08,R0
@@28:	MVO R0,_music_s7

@@27:	MVI _music_n8,R0	; Read drum
	DECR R0		; There is drum?
	BMI @@0		; No, jump
	MVI _music_s8,R1
	       		; 1 - Strong
	BNE @@29
	CMPI #3,R1
	BGE @@31
@@32:	MVII #5,R0
	MVO R0,_music2_noise
	CALL _activate_drum_ecs
	B @@31

@@29:	DECR R0		;2 - Short
	BNE @@30
	TSTR R1
	BNE @@31
	MVII #8,R0
	MVO R0,_music2_noise
	CALL _activate_drum_ecs
	B @@31

@@30:	;DECR R0	; 3 - Rolling
	;BNE @@31
	CMPI #2,R1
	BLT @@32
	MVI _music_t,R0
	SLR R0,1
	CMPR R0,R1
	BLT @@31
	ADDI #2,R0
	CMPR R0,R1
	BLT @@32
	; Increase time for drum waveform
@@31:	INCR R1
	MVO R1,_music_s8

    ENDI
@@0:	RETURN
	ENDP

	;
	; Translates note number to frequency
	; R3 = Note
	; R1 = Position in waveform for instrument
	; R2 = Instrument
	;
_note2freq:	PROC
	ADD _music_table,R3
	MVI@ R3,R3
	SWAP R2
	BEQ _piano_instrument
	RLC R2,1
	BNC _clarinet_instrument
	BPL _flute_instrument
;	BMI _bass_instrument
	ENDP

	;
	; Generates a bass
	;
_bass_instrument:	PROC
	SLL R3,2	; Lower 2 octaves
	ADDI #_bass_volume,R1
	MVI@ R1,R1	; Bass effect
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_bass_volume:	PROC
	DECLE 12,13,14,14,13,12,12,12
	DECLE 11,11,12,12,11,11,12,12
	DECLE 11,11,12,12,11,11,12,12
	ENDP

	;
	; Generates a piano
	; R3 = Frequency
	; R1 = Waveform position
	;
	; Output:
	; R3 = Frequency.
	; R1 = Volume.
	;
_piano_instrument:	PROC
	ADDI #_piano_volume,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_piano_volume:	PROC
	DECLE 14,13,13,12,12,11,11,10
	DECLE 10,9,9,8,8,7,7,6
	DECLE 6,6,7,7,6,6,5,5
	ENDP

	;
	; Generate a clarinet
	; R3 = Frequency
	; R1 = Waveform position
	;
	; Output:
	; R3 = Frequency
	; R1 = Volume
	;
_clarinet_instrument:	PROC
	ADDI #_clarinet_vibrato,R1
	ADD@ R1,R3
	CLRC
	RRC R3,1	; Duplicates frequency
	ADCR R3
	ADDI #_clarinet_volume-_clarinet_vibrato,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_clarinet_vibrato:	PROC
	DECLE 0,0,0,0
	DECLE -2,-4,-2,0
	DECLE 2,4,2,0
	DECLE -2,-4,-2,0
	DECLE 2,4,2,0
	DECLE -2,-4,-2,0
	ENDP

_clarinet_volume:	PROC
	DECLE 13,14,14,13,13,12,12,12
	DECLE 11,11,11,11,12,12,12,12
	DECLE 11,11,11,11,12,12,12,12
	ENDP

	;
	; Generates a flute
	; R3 = Frequency
	; R1 = Waveform position
	;
	; Output:
	; R3 = Frequency
	; R1 = Volume
	;
_flute_instrument:	PROC
	ADDI #_flute_vibrato,R1
	ADD@ R1,R3
	ADDI #_flute_volume-_flute_vibrato,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_flute_vibrato:	PROC
	DECLE 0,0,0,0
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	ENDP
		 
_flute_volume:	PROC
	DECLE 10,12,13,13,12,12,12,12
	DECLE 11,11,11,11,10,10,10,10
	DECLE 11,11,11,11,10,10,10,10
	ENDP

    IF DEFINED intybasic_music_volume

_global_volume:	PROC
	MVI _music_vol,R2
	ANDI #$0F,R2
	SLL R2,2
	SLL R2,2
	ADDR R1,R2
	ADDI #@@table,R2
	MVI@ R2,R1
	JR R5

@@table:
	DECLE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	DECLE 0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1
	DECLE 0,0,0,0,1,1,1,1,1,1,1,2,2,2,2,2
	DECLE 0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3
	DECLE 0,0,1,1,1,1,2,2,2,2,3,3,3,4,4,4
	DECLE 0,0,1,1,1,2,2,2,3,3,3,4,4,4,5,5
	DECLE 0,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6
	DECLE 0,1,1,1,2,2,3,3,4,4,5,5,6,6,7,7
	DECLE 0,1,1,2,2,3,3,4,4,5,5,6,6,7,8,8
	DECLE 0,1,1,2,2,3,4,4,5,5,6,7,7,8,8,9
	DECLE 0,1,1,2,3,3,4,5,5,6,7,7,8,9,9,10
	DECLE 0,1,2,2,3,4,4,5,6,7,7,8,9,10,10,11
	DECLE 0,1,2,2,3,4,5,6,6,7,8,9,10,10,11,12
	DECLE 0,1,2,3,4,4,5,6,7,8,9,10,10,11,12,13
	DECLE 0,1,2,3,4,5,6,7,8,8,9,10,11,12,13,14
	DECLE 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

	ENDP

    ENDI

    IF DEFINED intybasic_music_ecs
	;
	; Emits sound for ECS
	;
_emit_sound_ecs:	PROC
	MOVR R5,R1
	MVI _music_mode,R2
	SARC R2,1
	BEQ @@6
	MVII #_music2_freq10,R4
	MVII #$00F0,R5
	B _emit_sound.0

@@6:	JR R1

	ENDP

    ENDI

	;
	; Emits sound
	;
_emit_sound:	PROC
	MOVR R5,R1
	MVI _music_mode,R2
	SARC R2,1
	BEQ @@6
	MVII #_music_freq10,R4
	MVII #$01F0,R5
@@0:
	MVI@ R4,R0
	MVO@ R0,R5	; $01F0 - Channel A Period (Low 8 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F1 - Channel B Period (Low 8 bits of 12)
	DECR R2
	BEQ @@1
	MVI@ R4,R0	
	MVO@ R0,R5	; $01F2 - Channel C Period (Low 8 bits of 12)
	INCR R5		; Avoid $01F3 - Enveloped Period (Low 8 bits of 16)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F4 - Channel A Period (High 4 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F5 - Channel B Period (High 4 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F6 - Channel C Period (High 4 bits of 12)
	INCR R5		; Avoid $01F7 - Envelope Period (High 8 bits of 16)
	BC @@2		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@3

@@2:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8 - Enable Noise/Tone (bits 3-5 Noise : 0-2 Tone)
	MVI@ R4,R0	
	MVO@ R0,R5	; $01F9 - Noise Period (5 bits)
	INCR R5		; Avoid $01FA - Envelope Type (4 bits)
@@3:	MVI@ R4,R0
	MVO@ R0,R5	; $01FB - Channel A Volume
	MVI@ R4,R0
	MVO@ R0,R5	; $01FC - Channel B Volume
	MVI@ R4,R0
	MVO@ R0,R5	; $01FD - Channel C Volume
	JR R1

@@1:	INCR R4		
	INCR R5		; Avoid $01F2 and $01F3
	INCR R5		; Cannot use ADDI
	MVI@ R4,R0
	MVO@ R0,R5	; $01F4 - Channel A Period (High 4 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F5 - Channel B Period (High 4 bits of 12)
	INCR R4
	INCR R5		; Avoid $01F6 and $01F7
	INCR R5		; Cannot use ADDI
	BC @@4		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@5

@@4:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8 - Enable Noise/Tone (bits 3-5 Noise : 0-2 Tone)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F9 - Noise Period (5 bits)
	INCR R5		; Avoid $01FA - Envelope Type (4 bits)
@@5:	MVI@ R4,R0
	MVO@ R0,R5	; $01FB - Channel A Volume
	MVI@ R4,R0
	MVO@ R0,R5	; $01FC - Channel B Volume
@@6:	JR R1
	ENDP

	;
	; Activates drum
	;
_activate_drum:	PROC
    IF DEFINED intybasic_music_volume
	BEGIN
    ENDI
	MVI _music_mode,R2
	SARC R2,1	; PLAY NO DRUMS?
	BNC @@0		; Yes, jump
	MVI _music_vol1,R0
	TSTR R0
	BNE @@1
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol1
	MVI _music_mix,R0
	ANDI #$F6,R0
	XORI #$01,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@1:    MVI _music_vol2,R0
	TSTR R0
	BNE @@2
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol2
	MVI _music_mix,R0
	ANDI #$ED,R0
	XORI #$02,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@2:    DECR R2		; PLAY SIMPLE?
	BEQ @@3		; Yes, jump
	MVI _music_vol3,R0
	TSTR R0
	BNE @@3
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol3
	MVI _music_mix,R0
	ANDI #$DB,R0
	XORI #$04,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@3:    MVI _music_mix,R0
	ANDI #$EF,R0
	MVO R0,_music_mix
@@0:	
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

	ENDP

    IF DEFINED intybasic_music_ecs
	;
	; Activates drum
	;
_activate_drum_ecs:	PROC
    IF DEFINED intybasic_music_volume
	BEGIN
    ENDI
	MVI _music_mode,R2
	SARC R2,1	; PLAY NO DRUMS?
	BNC @@0		; Yes, jump
	MVI _music2_vol1,R0
	TSTR R0
	BNE @@1
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music2_vol1
	MVI _music2_mix,R0
	ANDI #$F6,R0
	XORI #$01,R0
	MVO R0,_music2_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@1:    MVI _music2_vol2,R0
	TSTR R0
	BNE @@2
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music2_vol2
	MVI _music2_mix,R0
	ANDI #$ED,R0
	XORI #$02,R0
	MVO R0,_music2_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@2:    DECR R2		; PLAY SIMPLE?
	BEQ @@3		; Yes, jump
	MVI _music2_vol3,R0
	TSTR R0
	BNE @@3
	MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music2_vol3
	MVI _music2_mix,R0
	ANDI #$DB,R0
	XORI #$04,R0
	MVO R0,_music2_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@3:    MVI _music2_mix,R0
	ANDI #$EF,R0
	MVO R0,_music2_mix
@@0:	
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

	ENDP

    ENDI

    ENDI
    
    IF DEFINED intybasic_numbers

	;
	; Following code from as1600 libraries, prnum16.asm
	; Public domain by Joseph Zbiciak
	;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008				     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  _PW10								   ;;
;;      Lookup table holding the first 5 powers of 10 (1 thru 10000) as     ;;
;;      16-bit numbers.						     ;;
;; ======================================================================== ;;
_PW10   PROC    ; 0 thru 10000
	DECLE   10000, 1000, 100, 10, 1, 0
	ENDP

;; ======================================================================== ;;
;;  PRNUM16.l     -- Print an unsigned 16-bit number left-justified.	;;
;;  PRNUM16.b     -- Print an unsigned 16-bit number with leading blanks.   ;;
;;  PRNUM16.z     -- Print an unsigned 16-bit number with leading zeros.    ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak  <im14u2c AT globalcrossing DOT net>		 ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      30-Mar-2003 Initial complete revision			       ;;
;;									  ;;
;;  INPUTS for all variants						 ;;
;;      R0  Number to print.						;;
;;      R2  Width of field.  Ignored by PRNUM16.l.			  ;;
;;      R3  Format word, added to digits to set the color.		  ;;
;;	  Note:  Bit 15 MUST be cleared when building with PRNUM32.       ;;
;;      R4  Pointer to location on screen to print number		   ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0  Zeroed							  ;;
;;      R1  Unmodified						      ;;
;;      R2  Unmodified						      ;;
;;      R3  Unmodified						      ;;
;;      R4  Points to first character after field.			  ;;
;;									  ;;
;;  DESCRIPTION							     ;;
;;      These routines print unsigned 16-bit numbers in a field up to 5     ;;
;;      positions wide.  The number is printed either in left-justified     ;;
;;      or right-justified format.  Right-justified numbers are padded      ;;
;;      with leading blanks or leading zeros.  Left-justified numbers       ;;
;;      are not padded on the right.					;;
;;									  ;;
;;      This code handles fields wider than 5 characters, padding with      ;;
;;      zeros or blanks as necessary.				       ;;
;;									  ;;
;;	      Routine      Value(hex)     Field	Output	     ;;
;;	      ----------   ----------   ----------   ----------	   ;;
;;	      PRNUM16.l      $0045	 n/a	"69"		;;
;;	      PRNUM16.b      $0045	  4	 "  69"	      ;;
;;	      PRNUM16.b      $0045	  6	 "    69"	    ;;
;;	      PRNUM16.z      $0045	  4	 "0069"	      ;;
;;	      PRNUM16.z      $0045	  6	 "000069"	    ;;
;;									  ;;
;;  TECHNIQUES							      ;;
;;      This routine uses repeated subtraction to divide the number	 ;;
;;      to display by various powers of 10.  This is cheaper than a	 ;;
;;      full divide, at least when the input number is large.  It's	 ;;
;;      also easier to get right.  :-)				      ;;
;;									  ;;
;;      The printing routine first pads out fields wider than 5 spaces      ;;
;;      with zeros or blanks as requested.  It then scans the power-of-10   ;;
;;      table looking for the first power of 10 that is <= the number to    ;;
;;      display.  While scanning for this power of 10, it outputs leading   ;;
;;      blanks or zeros, if requested.  This eliminates "leading digit"     ;;
;;      logic from the main digit loop.				     ;;
;;									  ;;
;;      Once in the main digit loop, we discover the value of each digit    ;;
;;      by repeated subtraction.  We build up our digit value while	 ;;
;;      subtracting the power-of-10 repeatedly.  We iterate until we go     ;;
;;      a step too far, and then we add back on power-of-10 to restore      ;;
;;      the remainder.						      ;;
;;									  ;;
;;  NOTES								   ;;
;;      The left-justified variant ignores field width.		     ;;
;;									  ;;
;;      The code is fully reentrant.					;;
;;									  ;;
;;      This code does not handle numbers which are too large to be	 ;;
;;      displayed in the provided field.  If the number is too large,       ;;
;;      non-digit characters will be displayed in the initial digit	 ;;
;;      position.  Also, the run time of this routine may get excessively   ;;
;;      large, depending on the magnitude of the overflow.		  ;;
;;									  ;;
;;      When using with PRNUM32, one must either include PRNUM32 before     ;;
;;      this function, or define the symbol _WITH_PRNUM32.  PRNUM32	 ;;
;;      needs a tiny bit of support from PRNUM16 to handle numbers in       ;;
;;      the range 65536...99999 correctly.				  ;;
;;									  ;;
;;  CODESIZE								;;
;;      73 words, including power-of-10 table			       ;;
;;      80 words, if compiled with PRNUM32.				 ;;
;;									  ;;
;;      To save code size, you can define the following symbols to omit     ;;
;;      some variants:						      ;;
;;									  ;;
;;	  _NO_PRNUM16.l:   Disables PRNUM16.l.  Saves 10 words	    ;;
;;	  _NO_PRNUM16.b:   Disables PRNUM16.b.  Saves 3 words.	    ;;
;;									  ;;
;;      Defining both symbols saves 17 words total, because it omits	;;
;;      some code shared by both routines.				  ;;
;;									  ;;
;;  STACK USAGE							     ;;
;;      This function uses up to 4 words of stack space.		    ;;
;; ======================================================================== ;;

PRNUM16 PROC

    
	;; ---------------------------------------------------------------- ;;
	;;  PRNUM16.l:  Print unsigned, left-justified.		     ;;
	;; ---------------------------------------------------------------- ;;
@@l:    PSHR    R5	      ; save return address
@@l1:   MVII    #$1,    R5      ; set R5 to 1 to counteract screen ptr update
				; in the 'find initial power of 10' loop
	PSHR    R2
	MVII    #5,     R2      ; force effective field width to 5.
	B       @@z2

	;; ---------------------------------------------------------------- ;;
	;;  PRNUM16.b:  Print unsigned with leading blanks.		 ;;
	;; ---------------------------------------------------------------- ;;
@@b:    PSHR    R5
@@b1:   CLRR    R5	      ; let the blank loop do its thing
	INCR    PC	      ; skip the PSHR R5

	;; ---------------------------------------------------------------- ;;
	;;  PRNUM16.z:  Print unsigned with leading zeros.		  ;;
	;; ---------------------------------------------------------------- ;;
@@z:    PSHR    R5
@@z1:   PSHR    R2
@@z2:   PSHR    R1

	;; ---------------------------------------------------------------- ;;
	;;  Find the initial power of 10 to use for display.		;;
	;;  Note:  For fields wider than 5, fill the extra spots above 5    ;;
	;;  with blanks or zeros as needed.				 ;;
	;; ---------------------------------------------------------------- ;;
	MVII    #_PW10+5,R1     ; Point to end of power-of-10 table
	SUBR    R2,     R1      ; Subtract the field width to get right power
	PSHR    R3	      ; save format word

	CMPI    #2,     R5      ; are we leading with zeros?
	BNC     @@lblnk	 ; no:  then do the loop w/ blanks

	CLRR    R5	      ; force R5==0
	ADDI    #$80,   R3      ; yes: do the loop with zeros
	B       @@lblnk
    

@@llp   MVO@    R3,     R4      ; print a blank/zero

	SUBR    R5,     R4      ; rewind pointer if needed.

	INCR    R1	      ; get next power of 10
@@lblnk DECR    R2	      ; decrement available digits
	BEQ     @@ldone
	CMPI    #5,     R2      ; field too wide?
	BGE     @@llp	   ; just force blanks/zeros 'till we're narrower.
	CMP@    R1,     R0      ; Is this power of 10 too big?
	BNC     @@llp	   ; Yes:  Put a blank and go to next

@@ldone PULR    R3	      ; restore format word

	;; ---------------------------------------------------------------- ;;
	;;  The digit loop prints at least one digit.  It discovers digits  ;;
	;;  by repeated subtraction.					;;
	;; ---------------------------------------------------------------- ;;
@@digit TSTR    R0	      ; If the number is zero, print zero and leave
	BNEQ    @@dig1	  ; no: print the number

	MOVR    R3,     R5      ;\    
	ADDI    #$80,   R5      ; |-- print a 0 there.
	MVO@    R5,     R4      ;/    
	B       @@done

@@dig1:
    
@@nxdig MOVR    R3,     R5      ; save display format word
@@cont: ADDI    #$80-8, R5      ; start our digit as one just before '0'
@@spcl:
 
	;; ---------------------------------------------------------------- ;;
	;;  Divide by repeated subtraction.  This divide is constructed     ;;
	;;  to go "one step too far" and then back up.		      ;;
	;; ---------------------------------------------------------------- ;;
@@div:  ADDI    #8,     R5      ; increment our digit
	SUB@    R1,     R0      ; subtract power of 10
	BC      @@div	   ; loop until we go too far
	ADD@    R1,     R0      ; add back the extra power of 10.

	MVO@    R5,     R4      ; display the digit.

	INCR    R1	      ; point to next power of 10
	DECR    R2	      ; any room left in field?
	BPL     @@nxdig	 ; keep going until R2 < 0.

@@done: PULR    R1	      ; restore R1
	PULR    R2	      ; restore R2
	PULR    PC	      ; return

	ENDP
	
    ENDI

    IF DEFINED intybasic_voice
;;==========================================================================;;
;;  SP0256-AL2 Allophones						   ;;
;;									  ;;
;;  This file contains the allophone set that was obtained from an	  ;;
;;  SP0256-AL2.  It is being provided for your convenience.		 ;;
;;									  ;;
;;  The directory "al2" contains a series of assembly files, each one       ;;
;;  containing a single allophone.  This series of files may be useful in   ;;
;;  situations where space is at a premium.				 ;;
;;									  ;;
;;  Consult the Archer SP0256-AL2 documentation (under doc/programming)     ;;
;;  for more information about SP0256-AL2's allophone library.	      ;;
;;									  ;;
;; ------------------------------------------------------------------------ ;;
;;									  ;;
;;  Copyright information:						  ;;
;;									  ;;
;;  The allophone data below was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is	   ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY	 ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.				       ;;
;;									  ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms	;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.				   ;;
;;									  ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;									  ;;
;;==========================================================================;;

;; ------------------------------------------------------------------------ ;;
_AA:
    DECLE   _AA.end - _AA - 1
    DECLE   $0318, $014C, $016F, $02CE, $03AF, $015F, $01B1, $008E
    DECLE   $0088, $0392, $01EA, $024B, $03AA, $039B, $000F, $0000
_AA.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_AE1:
    DECLE   _AE1.end - _AE1 - 1
    DECLE   $0118, $038E, $016E, $01FC, $0149, $0043, $026F, $036E
    DECLE   $01CC, $0005, $0000
_AE1.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AO:
    DECLE   _AO.end - _AO - 1
    DECLE   $0018, $010E, $016F, $0225, $00C6, $02C4, $030F, $0160
    DECLE   $024B, $0005, $0000
_AO.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AR:
    DECLE   _AR.end - _AR - 1
    DECLE   $0218, $010C, $016E, $001E, $000B, $0091, $032F, $00DE
    DECLE   $018B, $0095, $0003, $0238, $0027, $01E0, $03E8, $0090
    DECLE   $0003, $01C7, $0020, $03DE, $0100, $0190, $01CA, $02AB
    DECLE   $00B7, $004A, $0386, $0100, $0144, $02B6, $0024, $0320
    DECLE   $0011, $0041, $01DF, $0316, $014C, $016E, $001E, $00C4
    DECLE   $02B2, $031E, $0264, $02AA, $019D, $01BE, $000B, $00F0
    DECLE   $006A, $01CE, $00D6, $015B, $03B5, $03E4, $0000, $0380
    DECLE   $0007, $0312, $03E8, $030C, $016D, $02EE, $0085, $03C2
    DECLE   $03EC, $0283, $024A, $0005, $0000
_AR.end:  ; 69 decles
;; ------------------------------------------------------------------------ ;;
_AW:
    DECLE   _AW.end - _AW - 1
    DECLE   $0010, $01CE, $016E, $02BE, $0375, $034F, $0220, $0290
    DECLE   $008A, $026D, $013F, $01D5, $0316, $029F, $02E2, $018A
    DECLE   $0170, $0035, $00BD, $0000, $0000
_AW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_AX:
    DECLE   _AX.end - _AX - 1
    DECLE   $0218, $02CD, $016F, $02F5, $0386, $00C2, $00CD, $0094
    DECLE   $010C, $0005, $0000
_AX.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AY:
    DECLE   _AY.end - _AY - 1
    DECLE   $0110, $038C, $016E, $03B7, $03B3, $02AF, $0221, $009E
    DECLE   $01AA, $01B3, $00BF, $02E7, $025B, $0354, $00DA, $017F
    DECLE   $018A, $03F3, $00AF, $02D5, $0356, $027F, $017A, $01FB
    DECLE   $011E, $01B9, $03E5, $029F, $025A, $0076, $0148, $0124
    DECLE   $003D, $0000
_AY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_BB1:
    DECLE   _BB1.end - _BB1 - 1
    DECLE   $0318, $004C, $016C, $00FB, $00C7, $0144, $002E, $030C
    DECLE   $010E, $018C, $01DC, $00AB, $00C9, $0268, $01F7, $021D
    DECLE   $01B3, $0098, $0000
_BB1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_BB2:
    DECLE   _BB2.end - _BB2 - 1
    DECLE   $00F4, $0046, $0062, $0200, $0221, $03E4, $0087, $016F
    DECLE   $02A6, $02B7, $0212, $0326, $0368, $01BF, $0338, $0196
    DECLE   $0002
_BB2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_CH:
    DECLE   _CH.end - _CH - 1
    DECLE   $00F5, $0146, $0052, $0000, $032A, $0049, $0032, $02F2
    DECLE   $02A5, $0000, $026D, $0119, $0124, $00F6, $0000
_CH.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_DD1:
    DECLE   _DD1.end - _DD1 - 1
    DECLE   $0318, $034C, $016E, $0397, $01B9, $0020, $02B1, $008E
    DECLE   $0349, $0291, $01D8, $0072, $0000
_DD1.end:  ; 13 decles
;; ------------------------------------------------------------------------ ;;
_DD2:
    DECLE   _DD2.end - _DD2 - 1
    DECLE   $00F4, $00C6, $00F2, $0000, $0129, $00A6, $0246, $01F3
    DECLE   $02C6, $02B7, $028E, $0064, $0362, $01CF, $0379, $01D5
    DECLE   $0002
_DD2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_DH1:
    DECLE   _DH1.end - _DH1 - 1
    DECLE   $0018, $034F, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_DH2:
    DECLE   _DH2.end - _DH2 - 1
    DECLE   $0119, $034C, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_EH:
    DECLE   _EH.end - _EH - 1
    DECLE   $0218, $02CD, $016F, $0105, $014B, $0224, $02CF, $0274
    DECLE   $014C, $0005, $0000
_EH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_EL:
    DECLE   _EL.end - _EL - 1
    DECLE   $0118, $038D, $016E, $011C, $008B, $03D2, $030F, $0262
    DECLE   $006C, $019D, $01CC, $022B, $0170, $0078, $03FE, $0018
    DECLE   $0183, $03A3, $010D, $016E, $012E, $00C6, $00C3, $0300
    DECLE   $0060, $000D, $0005, $0000
_EL.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_ER1:
    DECLE   _ER1.end - _ER1 - 1
    DECLE   $0118, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0188
    DECLE   $01DA, $00CB, $00E7, $0048, $03A6, $0244, $016C, $01A8
    DECLE   $03E4, $0000, $0002, $0001, $00FC, $01DA, $02E4, $0000
    DECLE   $0002, $0008, $0200, $0217, $0164, $0000, $000E, $0038
    DECLE   $0014, $01EA, $0264, $0000, $0002, $0048, $01EC, $02F1
    DECLE   $03CC, $016D, $021E, $0048, $00C2, $034E, $036A, $000D
    DECLE   $008D, $000B, $0200, $0047, $0022, $03A8, $0000, $0000
_ER1.end:  ; 64 decles
;; ------------------------------------------------------------------------ ;;
_ER2:
    DECLE   _ER2.end - _ER2 - 1
    DECLE   $0218, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0190
    DECLE   $01D8, $00CB, $00E7, $0058, $01A6, $0244, $0164, $02A9
    DECLE   $0024, $0000, $0000, $0007, $0201, $02F8, $02E4, $0000
    DECLE   $0002, $0001, $00FC, $02DA, $0024, $0000, $0002, $0008
    DECLE   $0200, $0217, $0024, $0000, $000E, $0038, $0014, $03EA
    DECLE   $03A4, $0000, $0002, $0048, $01EC, $03F1, $038C, $016D
    DECLE   $021E, $0048, $00C2, $034E, $036A, $000D, $009D, $0003
    DECLE   $0200, $0047, $0022, $03A8, $0000, $0000
_ER2.end:  ; 70 decles
;; ------------------------------------------------------------------------ ;;
_EY:
    DECLE   _EY.end - _EY - 1
    DECLE   $0310, $038C, $016E, $02A7, $00BB, $0160, $0290, $0094
    DECLE   $01CA, $03A9, $00C1, $02D7, $015B, $01D4, $03CE, $02FF
    DECLE   $00EA, $03E7, $0041, $0277, $025B, $0355, $03C9, $0103
    DECLE   $02EA, $03E4, $003F, $0000
_EY.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_FF:
    DECLE   _FF.end - _FF - 1
    DECLE   $0119, $03C8, $0000, $00A7, $0094, $0138, $01C6, $0000
_FF.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_GG1:
    DECLE   _GG1.end - _GG1 - 1
    DECLE   $00F4, $00C6, $00C2, $0200, $0015, $03FE, $0283, $01FD
    DECLE   $01E6, $00B7, $030A, $0364, $0331, $017F, $033D, $0215
    DECLE   $0002
_GG1.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG2:
    DECLE   _GG2.end - _GG2 - 1
    DECLE   $00F4, $0106, $0072, $0300, $0021, $0308, $0039, $0173
    DECLE   $00C6, $00B7, $037E, $03A3, $0319, $0177, $0036, $0217
    DECLE   $0002
_GG2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG3:
    DECLE   _GG3.end - _GG3 - 1
    DECLE   $00F8, $0146, $00F2, $0100, $0132, $03A8, $0055, $01F5
    DECLE   $00A6, $02B7, $0291, $0326, $0368, $0167, $023A, $01C6
    DECLE   $0002
_GG3.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_HH1:
    DECLE   _HH1.end - _HH1 - 1
    DECLE   $0218, $01C9, $0000, $0095, $0127, $0060, $01D6, $0213
    DECLE   $0002, $01AE, $033E, $01A0, $03C4, $0122, $0001, $0218
    DECLE   $01E4, $03FD, $0019, $0000
_HH1.end:  ; 20 decles
;; ------------------------------------------------------------------------ ;;
_HH2:
    DECLE   _HH2.end - _HH2 - 1
    DECLE   $0218, $00CB, $0000, $0086, $000F, $0240, $0182, $031A
    DECLE   $02DB, $0008, $0293, $0067, $00BD, $01E0, $0092, $000C
    DECLE   $0000
_HH2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_IH:
    DECLE   _IH.end - _IH - 1
    DECLE   $0118, $02CD, $016F, $0205, $0144, $02C3, $00FE, $031A
    DECLE   $000D, $0005, $0000
_IH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_IY:
    DECLE   _IY.end - _IY - 1
    DECLE   $0318, $02CC, $016F, $0008, $030B, $01C3, $0330, $0178
    DECLE   $002B, $019D, $01F6, $018B, $01E1, $0010, $020D, $0358
    DECLE   $015F, $02A4, $02CC, $016F, $0109, $030B, $0193, $0320
    DECLE   $017A, $034C, $009C, $0017, $0001, $0200, $03C1, $0020
    DECLE   $00A7, $001D, $0001, $0104, $003D, $0040, $01A7, $01CA
    DECLE   $018B, $0160, $0078, $01F6, $0343, $01C7, $0090, $0000
_IY.end:  ; 48 decles
;; ------------------------------------------------------------------------ ;;
_JH:
    DECLE   _JH.end - _JH - 1
    DECLE   $0018, $0149, $0001, $00A4, $0321, $0180, $01F4, $039A
    DECLE   $02DC, $023C, $011A, $0047, $0200, $0001, $018E, $034E
    DECLE   $0394, $0356, $02C1, $010C, $03FD, $0129, $00B7, $01BA
    DECLE   $0000
_JH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_KK1:
    DECLE   _KK1.end - _KK1 - 1
    DECLE   $00F4, $00C6, $00D2, $0000, $023A, $03E0, $02D1, $02E5
    DECLE   $0184, $0200, $0041, $0210, $0188, $00C5, $0000
_KK1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_KK2:
    DECLE   _KK2.end - _KK2 - 1
    DECLE   $021D, $023C, $0211, $003C, $0180, $024D, $0008, $032B
    DECLE   $025B, $002D, $01DC, $01E3, $007A, $0000
_KK2.end:  ; 14 decles
;; ------------------------------------------------------------------------ ;;
_KK3:
    DECLE   _KK3.end - _KK3 - 1
    DECLE   $00F7, $0046, $01D2, $0300, $0131, $006C, $006E, $00F1
    DECLE   $00E4, $0000, $025A, $010D, $0110, $01F9, $014A, $0001
    DECLE   $00B5, $01A2, $00D8, $01CE, $0000
_KK3.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_LL:
    DECLE   _LL.end - _LL - 1
    DECLE   $0318, $038C, $016D, $029E, $0333, $0260, $0221, $0294
    DECLE   $01C4, $0299, $025A, $00E6, $014C, $012C, $0031, $0000
_LL.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_MM:
    DECLE   _MM.end - _MM - 1
    DECLE   $0210, $034D, $016D, $03F5, $00B0, $002E, $0220, $0290
    DECLE   $03CE, $02B6, $03AA, $00F3, $00CF, $015D, $016E, $0000
_MM.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_NG1:
    DECLE   _NG1.end - _NG1 - 1
    DECLE   $0118, $03CD, $016E, $00DC, $032F, $01BF, $01E0, $0116
    DECLE   $02AB, $029A, $0358, $01DB, $015B, $01A7, $02FD, $02B1
    DECLE   $03D2, $0356, $0000
_NG1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_NN1:
    DECLE   _NN1.end - _NN1 - 1
    DECLE   $0318, $03CD, $016C, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $009D, $000D, $0248, $01B4, $0120, $01E1, $00C8
    DECLE   $0003, $0040, $0000, $0080, $015F, $0006, $0000
_NN1.end:  ; 23 decles
;; ------------------------------------------------------------------------ ;;
_NN2:
    DECLE   _NN2.end - _NN2 - 1
    DECLE   $0018, $034D, $016D, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $0095, $0003, $0248, $01B4, $0120, $01E1, $0090
    DECLE   $000B, $0040, $0000, $0080, $015F, $019E, $01F6, $028B
    DECLE   $00E0, $0266, $03F6, $01D8, $0143, $01A8, $0024, $00C0
    DECLE   $0080, $0000, $01E6, $0321, $0024, $0260, $000A, $0008
    DECLE   $03FE, $0000, $0000
_NN2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_OR2:
    DECLE   _OR2.end - _OR2 - 1
    DECLE   $0218, $018C, $016D, $02A6, $03AB, $004F, $0301, $0390
    DECLE   $02EA, $0289, $0228, $0356, $01CF, $02D5, $0135, $007D
    DECLE   $02B5, $02AF, $024A, $02E2, $0153, $0167, $0333, $02A9
    DECLE   $02B3, $039A, $0351, $0147, $03CD, $0339, $02DA, $0000
_OR2.end:  ; 32 decles
;; ------------------------------------------------------------------------ ;;
_OW:
    DECLE   _OW.end - _OW - 1
    DECLE   $0310, $034C, $016E, $02AE, $03B1, $00CF, $0304, $0192
    DECLE   $018A, $022B, $0041, $0277, $015B, $0395, $03D1, $0082
    DECLE   $03CE, $00B6, $03BB, $02DA, $0000
_OW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_OY:
    DECLE   _OY.end - _OY - 1
    DECLE   $0310, $014C, $016E, $02A6, $03AF, $00CF, $0304, $0192
    DECLE   $03CA, $01A8, $007F, $0155, $02B4, $027F, $00E2, $036A
    DECLE   $031F, $035D, $0116, $01D5, $02F4, $025F, $033A, $038A
    DECLE   $014F, $01B5, $03D5, $0297, $02DA, $03F2, $0167, $0124
    DECLE   $03FB, $0001
_OY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_PA1:
    DECLE   _PA1.end - _PA1 - 1
    DECLE   $00F1, $0000
_PA1.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA2:
    DECLE   _PA2.end - _PA2 - 1
    DECLE   $00F4, $0000
_PA2.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA3:
    DECLE   _PA3.end - _PA3 - 1
    DECLE   $00F7, $0000
_PA3.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA4:
    DECLE   _PA4.end - _PA4 - 1
    DECLE   $00FF, $0000
_PA4.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA5:
    DECLE   _PA5.end - _PA5 - 1
    DECLE   $031D, $003F, $0000
_PA5.end:  ; 3 decles
;; ------------------------------------------------------------------------ ;;
_PP:
    DECLE   _PP.end - _PP - 1
    DECLE   $00FD, $0106, $0052, $0000, $022A, $03A5, $0277, $035F
    DECLE   $0184, $0000, $0055, $0391, $00EB, $00CF, $0000
_PP.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_RR1:
    DECLE   _RR1.end - _RR1 - 1
    DECLE   $0118, $01CD, $016C, $029E, $0171, $038E, $01E0, $0190
    DECLE   $0245, $0299, $01AA, $02E2, $01C7, $02DE, $0125, $00B5
    DECLE   $02C5, $028F, $024E, $035E, $01CB, $02EC, $0005, $0000
_RR1.end:  ; 24 decles
;; ------------------------------------------------------------------------ ;;
_RR2:
    DECLE   _RR2.end - _RR2 - 1
    DECLE   $0218, $03CC, $016C, $030C, $02C8, $0393, $02CD, $025E
    DECLE   $008A, $019D, $01AC, $02CB, $00BE, $0046, $017E, $01C2
    DECLE   $0174, $00A1, $01E5, $00E0, $010E, $0007, $0313, $0017
    DECLE   $0000
_RR2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SH:
    DECLE   _SH.end - _SH - 1
    DECLE   $0218, $0109, $0000, $007A, $0187, $02E0, $03F6, $0311
    DECLE   $0002, $0126, $0242, $0161, $03E9, $0219, $016C, $0300
    DECLE   $0013, $0045, $0124, $0005, $024C, $005C, $0182, $03C2
    DECLE   $0001
_SH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SS:
    DECLE   _SS.end - _SS - 1
    DECLE   $0218, $01CA, $0001, $0128, $001C, $0149, $01C6, $0000
_SS.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TH:
    DECLE   _TH.end - _TH - 1
    DECLE   $0019, $0349, $0000, $00C6, $0212, $01D8, $01CA, $0000
_TH.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TT1:
    DECLE   _TT1.end - _TT1 - 1
    DECLE   $00F6, $0046, $0142, $0100, $0042, $0088, $027E, $02EF
    DECLE   $01A4, $0200, $0049, $0290, $00FC, $00E8, $0000
_TT1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_TT2:
    DECLE   _TT2.end - _TT2 - 1
    DECLE   $00F5, $00C6, $01D2, $0100, $0335, $00E9, $0042, $027A
    DECLE   $02A4, $0000, $0062, $01D1, $014C, $03EA, $02EC, $01E0
    DECLE   $0007, $03A7, $0000
_TT2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_UH:
    DECLE   _UH.end - _UH - 1
    DECLE   $0018, $034E, $016E, $01FF, $0349, $00D2, $003C, $030C
    DECLE   $008B, $0005, $0000
_UH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_UW1:
    DECLE   _UW1.end - _UW1 - 1
    DECLE   $0318, $014C, $016F, $029E, $03BD, $03BD, $0271, $0212
    DECLE   $0325, $0291, $016A, $027B, $014A, $03B4, $0133, $0001
_UW1.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_UW2:
    DECLE   _UW2.end - _UW2 - 1
    DECLE   $0018, $034E, $016E, $02F6, $0107, $02C2, $006D, $0090
    DECLE   $03AC, $01A4, $01DC, $03AB, $0128, $0076, $03E6, $0119
    DECLE   $014F, $03A6, $03A5, $0020, $0090, $0001, $02EE, $00BB
    DECLE   $0000
_UW2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_VV:
    DECLE   _VV.end - _VV - 1
    DECLE   $0218, $030D, $016C, $010B, $010B, $0095, $034F, $03E4
    DECLE   $0108, $01B5, $01BE, $028B, $0160, $00AA, $03E4, $0106
    DECLE   $00EB, $02DE, $014C, $016E, $00F6, $0107, $00D2, $00CD
    DECLE   $0296, $00E4, $0006, $0000
_VV.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_WH:
    DECLE   _WH.end - _WH - 1
    DECLE   $0218, $00C9, $0000, $0084, $038E, $0147, $03A4, $0195
    DECLE   $0000, $012E, $0118, $0150, $02D1, $0232, $01B7, $03F1
    DECLE   $0237, $01C8, $03B1, $0227, $01AE, $0254, $0329, $032D
    DECLE   $01BF, $0169, $019A, $0307, $0181, $028D, $0000
_WH.end:  ; 31 decles
;; ------------------------------------------------------------------------ ;;
_WW:
    DECLE   _WW.end - _WW - 1
    DECLE   $0118, $034D, $016C, $00FA, $02C7, $0072, $03CC, $0109
    DECLE   $000B, $01AD, $019E, $016B, $0130, $0278, $01F8, $0314
    DECLE   $017E, $029E, $014D, $016D, $0205, $0147, $02E2, $001A
    DECLE   $010A, $026E, $0004, $0000
_WW.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_XR2:
    DECLE   _XR2.end - _XR2 - 1
    DECLE   $0318, $034C, $016E, $02A6, $03BB, $002F, $0290, $008E
    DECLE   $004B, $0392, $01DA, $024B, $013A, $01DA, $012F, $00B5
    DECLE   $02E5, $0297, $02DC, $0372, $014B, $016D, $0377, $00E7
    DECLE   $0376, $038A, $01CE, $026B, $02FA, $01AA, $011E, $0071
    DECLE   $00D5, $0297, $02BC, $02EA, $01C7, $02D7, $0135, $0155
    DECLE   $01DD, $0007, $0000
_XR2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_YR:
    DECLE   _YR.end - _YR - 1
    DECLE   $0318, $03CC, $016E, $0197, $00FD, $0130, $0270, $0094
    DECLE   $0328, $0291, $0168, $007E, $01CC, $02F5, $0125, $02B5
    DECLE   $00F4, $0298, $01DA, $03F6, $0153, $0126, $03B9, $00AB
    DECLE   $0293, $03DB, $0175, $01B9, $0001
_YR.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY1:
    DECLE   _YY1.end - _YY1 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0001, $0000
_YY1.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY2:
    DECLE   _YY2.end - _YY2 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0199, $01EE, $008B, $0161, $0232
    DECLE   $0004, $0318, $01A7, $0198, $0124, $03E0, $0001, $0001
    DECLE   $030F, $0027, $0000
_YY2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_ZH:
    DECLE   _ZH.end - _ZH - 1
    DECLE   $0310, $014D, $016E, $00C3, $03B9, $01BF, $0241, $0012
    DECLE   $0163, $00E1, $0000, $0080, $0084, $023F, $003F, $0000
_ZH.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_ZZ:
    DECLE   _ZZ.end - _ZZ - 1
    DECLE   $0218, $010D, $016F, $0225, $0351, $00B5, $02A0, $02EE
    DECLE   $00E9, $014D, $002C, $0360, $0008, $00EC, $004C, $0342
    DECLE   $03D4, $0156, $0052, $0131, $0008, $03B0, $01BE, $0172
    DECLE   $0000
_ZZ.end:  ; 25 decles

;;==========================================================================;;
;;									  ;;
;;  Copyright information:						  ;;
;;									  ;;
;;  The above allophone data was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is	   ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY	 ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.				       ;;
;;									  ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms	;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.				   ;;
;;									  ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;									  ;;
;;==========================================================================;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008				     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  INTELLIVOICE DRIVER ROUTINES					    ;;
;;  Written in 2002 by Joe Zbiciak <intvnut AT gmail.com>		   ;;
;;  http://spatula-city.org/~im14u2c/intv/				  ;;
;; ======================================================================== ;;

;; ======================================================================== ;;
;;  GLOBAL VARIABLES USED BY THESE ROUTINES				 ;;
;;									  ;;
;;  Note that some of these routines may use one or more global variables.  ;;
;;  If you use these routines, you will need to allocate the appropriate    ;;
;;  space in either 16-bit or 8-bit memory as appropriate.  Each global     ;;
;;  variable is listed with the routines which use it and the required      ;;
;;  memory width.							   ;;
;;									  ;;
;;  Example declarations for these routines are shown below, commented out. ;;
;;  You should uncomment these and add them to your program to make use of  ;;
;;  the routine that needs them.  Make sure to assign these variables to    ;;
;;  locations that aren't used for anything else.			   ;;
;; ======================================================================== ;;

			; Used by       Req'd Width     Description
			;-----------------------------------------------------
;IV.QH      EQU $110    ; IV_xxx	8-bit	   Voice queue head
;IV.QT      EQU $111    ; IV_xxx	8-bit	   Voice queue tail
;IV.Q       EQU $112    ; IV_xxx	8-bit	   Voice queue  (8 bytes)
;IV.FLEN    EQU $11A    ; IV_xxx	8-bit	   Length of FIFO data
;IV.FPTR    EQU $320    ; IV_xxx	16-bit	  Current FIFO ptr.
;IV.PPTR    EQU $321    ; IV_xxx	16-bit	  Current Phrase ptr.

;; ======================================================================== ;;
;;  MEMORY USAGE							    ;;
;;									  ;;
;;  These routines implement a queue of "pending phrases" that will be      ;;
;;  played by the Intellivoice.  The user calls IV_PLAY to enqueue a	;;
;;  phrase number.  Phrase numbers indicate either a RESROM sample or       ;;
;;  a compiled in phrase to be spoken.				      ;;
;;									  ;;
;;  The user must compose an "IV_PHRASE_TBL", which is composed of	  ;;
;;  pointers to phrases to be spoken.  Phrases are strings of pointers      ;;
;;  and RESROM triggers, terminated by a NUL.			       ;;
;;									  ;;
;;  Phrase numbers 1 through 42 are RESROM samples.  Phrase numbers	 ;;
;;  43 through 255 index into the IV_PHRASE_TBL.			    ;;
;;									  ;;
;;  SPECIAL NOTES							   ;;
;;									  ;;
;;  Bit 7 of IV.QH and IV.QT is used to denote whether the Intellivoice     ;;
;;  is present.  If Intellivoice is present, this bit is clear.	     ;;
;;									  ;;
;;  Bit 6 of IV.QT is used to denote that we still need to do an ALD $00    ;;
;;  for FIFO'd voice data.						  ;;
;; ======================================================================== ;;
	    

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_INIT     Initialize the Intellivoice			     ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_INIT						      ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0      0 if Intellivoice found, -1 if not.			 ;;
;;									  ;;
;;  DESCRIPTION							     ;;
;;      Resets Intellivoice, determines if it is actually there, and	;;
;;      then initializes the IV structure.				  ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;

IV_INIT     PROC
	    MVII    #$0400, R0	  ;
	    MVO     R0,     $0081       ; Reset the Intellivoice

	    MVI     $0081,  R0	  ; \
	    RLC     R0,     2	   ;  |-- See if we detect Intellivoice
	    BOV     @@no_ivoice	 ; /    once we've reset it.

	    CLRR    R0		  ; 
	    MVO     R0,     IV.FPTR     ; No data for FIFO
	    MVO     R0,     IV.PPTR     ; No phrase being spoken
	    MVO     R0,     IV.QH       ; Clear our queue
	    MVO     R0,     IV.QT       ; Clear our queue
	    JR      R5		  ; Done!

@@no_ivoice:
	    CLRR    R0
	    MVO     R0,     IV.FPTR     ; No data for FIFO
	    MVO     R0,     IV.PPTR     ; No phrase being spoken
	    DECR    R0
	    MVO     R0,     IV.QH       ; Set queue to -1 ("No Intellivoice")
	    MVO     R0,     IV.QT       ; Set queue to -1 ("No Intellivoice")
;	    JR      R5		 ; Done!
	    B       _wait	       ; Special for IntyBASIC!
	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_ISR      Interrupt service routine to feed Intellivoice	  ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_ISR						       ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0, R1, R4 trashed.						 ;;
;;									  ;;
;;  NOTES								   ;;
;;      Call this from your main interrupt service routine.		 ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_ISR      PROC
	    ;; ------------------------------------------------------------ ;;
	    ;;  Check for Intellivoice.  Leave if none present.	     ;;
	    ;; ------------------------------------------------------------ ;;
	    MVI     IV.QT,  R1	  ; Get queue tail
	    SWAP    R1,     2
	    BPL     @@ok		; Bit 7 set? If yes: No Intellivoice
@@ald_busy:
@@leave     JR      R5		  ; Exit if no Intellivoice.

     
	    ;; ------------------------------------------------------------ ;;
	    ;;  Check to see if we pump samples into the FIFO.
	    ;; ------------------------------------------------------------ ;;
@@ok:       MVI     IV.FPTR, R4	 ; Get FIFO data pointer
	    TSTR    R4		  ; is it zero?
	    BEQ     @@no_fifodata       ; Yes:  No data for FIFO.
@@fifo_fill:
	    MVI     $0081,  R0	  ; Read speech FIFO ready bit
	    SLLC    R0,     1	   ; 
	    BC      @@fifo_busy     

	    MVI@    R4,     R0	  ; Get next word
	    MVO     R0,     $0081       ; write it to the FIFO

	    MVI     IV.FLEN, R0	 ;\
	    DECR    R0		  ; |-- Decrement our FIFO'd data length
	    MVO     R0,     IV.FLEN     ;/
	    BEQ     @@last_fifo	 ; If zero, we're done w/ FIFO
	    MVO     R4,     IV.FPTR     ; Otherwise, save new pointer
	    B       @@fifo_fill	 ; ...and keep trying to load FIFO

@@last_fifo MVO     R0,     IV.FPTR     ; done with FIFO loading.
					; fall into ALD processing.


	    ;; ------------------------------------------------------------ ;;
	    ;;  Try to do an Address Load.  We do this in two settings:     ;;
	    ;;   -- We have no FIFO data to load.			   ;;
	    ;;   -- We've loaded as much FIFO data as we can, but we	;;
	    ;;      might have an address load command to send for it.      ;;
	    ;; ------------------------------------------------------------ ;;
@@fifo_busy:
@@no_fifodata:
	    MVI     $0080,  R0	  ; Read LRQ bit from ALD register
	    SLLC    R0,     1
	    BNC     @@ald_busy	  ; LRQ is low, meaning we can't ALD.
					; So, leave.

	    ;; ------------------------------------------------------------ ;;
	    ;;  We can do an address load (ALD) on the SP0256.  Give FIFO   ;;
	    ;;  driven ALDs priority, since we already started the FIFO     ;;
	    ;;  load.  The "need ALD" bit is stored in bit 6 of IV.QT.      ;;
	    ;; ------------------------------------------------------------ ;;
	    ANDI    #$40,   R1	  ; Is "Need FIFO ALD" bit set?
	    BEQ     @@no_fifo_ald
	    XOR     IV.QT,  R1	  ;\__ Clear the "Need FIFO ALD" bit.
	    MVO     R1,     IV.QT       ;/
	    CLRR    R1
	    MVO     R1,     $80	 ; Load a 0 into ALD (trigger FIFO rd.)
	    JR      R5		  ; done!

	    ;; ------------------------------------------------------------ ;;
	    ;;  We don't need to ALD on behalf of the FIFO.  So, we grab    ;;
	    ;;  the next thing off our phrase list.			 ;;
	    ;; ------------------------------------------------------------ ;;
@@no_fifo_ald:
	    MVI     IV.PPTR, R4	 ; Get phrase pointer.
	    TSTR    R4		  ; Is it zero?
	    BEQ     @@next_phrase       ; Yes:  Get next phrase from queue.

	    MVI@    R4,     R0
	    TSTR    R0		  ; Is it end of phrase?
	    BNEQ    @@process_phrase    ; !=0:  Go do it.

	    MVO     R0,     IV.PPTR     ; 
@@next_phrase:
	    MVI     IV.QT,  R1	  ; reload queue tail (was trashed above)
	    MOVR    R1,     R0	  ; copy QT to R0 so we can increment it
	    ANDI    #$7,    R1	  ; Mask away flags in queue head
	    CMP     IV.QH,  R1	  ; Is it same as queue tail?
	    BEQ     @@leave	     ; Yes:  No more speech for now.

	    INCR    R0
	    ANDI    #$F7,   R0	  ; mask away the possible 'carry'
	    MVO     R0,     IV.QT       ; save updated queue tail

	    ADDI    #IV.Q,  R1	  ; Index into queue
	    MVI@    R1,     R4	  ; get next value from queue
	    CMPI    #43,    R4	  ; Is it a RESROM or Phrase?
	    BNC     @@play_resrom_r4
@@new_phrase:
;	    ADDI    #IV_PHRASE_TBL - 43, R4 ; Index into phrase table
;	    MVI@    R4,     R4	  ; Read from phrase table
	    MVO     R4,     IV.PPTR
	    JR      R5		  ; we'll get to this phrase next time.

@@play_resrom_r4:
	    MVO     R4,     $0080       ; Just ALD it
	    JR      R5		  ; and leave.

	    ;; ------------------------------------------------------------ ;;
	    ;;  We're in the middle of a phrase, so continue interpreting.  ;;
	    ;; ------------------------------------------------------------ ;;
@@process_phrase:
	    
	    MVO     R4,     IV.PPTR     ; save new phrase pointer
	    CMPI    #43,    R0	  ; Is it a RESROM cue?
	    BC      @@play_fifo	 ; Just ALD it and leave.
@@play_resrom_r0
	    MVO     R0,     $0080       ; Just ALD it
	    JR      R5		  ; and leave.
@@play_fifo:
	    MVI     IV.FPTR,R1	  ; Make sure not to stomp existing FIFO
	    TSTR    R1		  ; data.
	    BEQ     @@new_fifo_ok
	    DECR    R4		  ; Oops, FIFO data still playing,
	    MVO     R4,     IV.PPTR     ; so rewind.
	    JR      R5		  ; and leave.

@@new_fifo_ok:
	    MOVR    R0,     R4	  ;
	    MVI@    R4,     R0	  ; Get chunk length
	    MVO     R0,     IV.FLEN     ; Init FIFO chunk length
	    MVO     R4,     IV.FPTR     ; Init FIFO pointer
	    MVI     IV.QT,  R0	  ;\
	    XORI    #$40,   R0	  ; |- Set "Need ALD" bit in QT
	    MVO     R0,     IV.QT       ;/

  IF 1      ; debug code		;\
	    ANDI    #$40,   R0	  ; |   Debug code:  We should only
	    BNEQ    @@qtok	      ; |-- be here if "Need FIFO ALD" 
	    HLT     ;BUG!!	      ; |   was already clear.	 
@@qtok				  ;/    
  ENDI
	    JR      R5		  ; leave.

	    ENDP


;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_PLAY     Play a voice sample sequence.			   ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_PLAY						      ;;
;;      R5      Invocation record, followed by return address.	      ;;
;;		  1 DECLE    Phrase number to play.		       ;;
;;									  ;;
;;  INPUTS for IV_PLAY.1						    ;;
;;      R0      Address of phrase to play.				  ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0, R1  trashed						     ;;
;;      Z==0    if item not successfully queued.			    ;;
;;      Z==1    if successfully queued.				     ;;
;;									  ;;
;;  NOTES								   ;;
;;      This code will drop phrases if the queue is full.		   ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index	;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the	 ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;									  ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_PLAY     PROC
	    MVI@    R5,     R0

@@1:	; alternate entry point
	    MVI     IV.QT,  R1	  ; Get queue tail
	    SWAP    R1,     2	   ;\___ Leave if "no Intellivoice"
	    BMI     @@leave	     ;/    bit it set.
@@ok:       
	    DECR    R1		  ;\
	    ANDI    #$7,    R1	  ; |-- See if we still have room
	    CMP     IV.QH,  R1	  ;/
	    BEQ     @@leave	     ; Leave if we're full

@@2:	MVI     IV.QH,  R1	  ; Get our queue head pointer
	    PSHR    R1		  ;\
	    INCR    R1		  ; |
	    ANDI    #$F7,   R1	  ; |-- Increment it, removing
	    MVO     R1,     IV.QH       ; |   carry but preserving flags.
	    PULR    R1		  ;/

	    ADDI    #IV.Q,  R1	  ;\__ Store phrase to queue
	    MVO@    R0,     R1	  ;/

@@leave:    JR      R5		  ; Leave.
	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_PLAYW    Play a voice sample sequence.  Wait for queue room.     ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_PLAY						      ;;
;;      R5      Invocation record, followed by return address.	      ;;
;;		  1 DECLE    Phrase number to play.		       ;;
;;									  ;;
;;  INPUTS for IV_PLAY.1						    ;;
;;      R0      Address of phrase to play.				  ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0, R1  trashed						     ;;
;;									  ;;
;;  NOTES								   ;;
;;      This code will wait for a queue slot to open if queue is full.      ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index	;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the	 ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;									  ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_PLAYW    PROC
	    MVI@    R5,     R0

@@1:	; alternate entry point
	    MVI     IV.QT,  R1	  ; Get queue tail
	    SWAP    R1,     2	   ;\___ Leave if "no Intellivoice"
	    BMI     IV_PLAY.leave       ;/    bit it set.
@@ok:       
	    DECR    R1		  ;\
	    ANDI    #$7,    R1	  ; |-- See if we still have room
	    CMP     IV.QH,  R1	  ;/
	    BEQ     @@1		 ; wait for room
	    B       IV_PLAY.2

	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_HUSH     Flush the speech queue, and hush the Intellivoice.      ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      02-Feb-2018 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_HUSH						      ;;
;;      None.							       ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0 trashed.							 ;;
;;									  ;;
;;  NOTES								   ;;
;;      Returns via IV_WAIT.						;;
;;									  ;;
;; ======================================================================== ;;
IV_HUSH:    PROC
	    MVI     IV.QH,  R0
	    SWAP    R0,     2
	    BMI     IV_WAIT.leave

	    DIS
	    ;; We can't stop a phrase segment that's being FIFOed down.
	    ;; We need to remember if we've committed to pushing ALD.
	    ;; We _can_ stop new phrase segments from going down, and _can_
	    ;; stop new phrases from being started.

	    ;; Set head pointer to indicate we've inserted one item.
	    MVI     IV.QH,  R0  ; Re-read, as an interrupt may have occurred
	    ANDI    #$F0,   R0
	    INCR    R0
	    MVO     R0,     IV.QH

	    ;; Reset tail pointer, keeping "need ALD" bit and other flags.
	    MVI     IV.QT,  R0
	    ANDI    #$F0,   R0
	    MVO     R0,     IV.QT

	    ;; Reset the phrase pointer, to stop a long phrase.
	    CLRR    R0
	    MVO     R0,     IV.PPTR

	    ;; Queue a PA1 in the queue.  Since we're can't guarantee the user
	    ;; has included resrom.asm, let's just use the raw number (5).
	    MVII    #5,     R0
	    MVO     R0,     IV.Q

	    ;; Re-enable interrupts and wait for Intellivoice to shut up.
	    ;;
	    ;; We can't just jump to IV_WAIT.q_loop, as we need to reload
	    ;; IV.QH into R0, and I'm really committed to only using R0.
;	   JE      IV_WAIT
	    EIS
	    ; fallthrough into IV_WAIT
	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_WAIT     Wait for voice queue to empty.			  ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_WAIT						      ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0      trashed.						    ;;
;;									  ;;
;;  NOTES								   ;;
;;      This waits until the Intellivoice is nearly completely quiescent.   ;;
;;      Some voice data may still be spoken from the last triggered	 ;;
;;      phrase.  To truly wait for *that* to be spoken, speak a 'pause'     ;;
;;      (eg. RESROM.pa1) and then call IV_WAIT.			     ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_WAIT     PROC
	    MVI     IV.QH,  R0
	    CMPI    #$80, R0	    ; test bit 7, leave if set.
	    BC      @@leave

	    ; Wait for queue to drain.
@@q_loop:   CMP     IV.QT,  R0
	    BNEQ    @@q_loop

	    ; Wait for FIFO and LRQ to say ready.
@@s_loop:   MVI     $81,    R0	  ; Read FIFO status.  0 == ready.
	    COMR    R0
	    AND     $80,    R0	  ; Merge w/ ALD status.  1 == ready
	    TSTR    R0
	    BPL     @@s_loop	    ; if bit 15 == 0, not ready.
	    
@@leave:    JR      R5
	    ENDP

;; ======================================================================== ;;
;;  End of File:  ivoice.asm						;;
;; ======================================================================== ;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008				     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_SAYNUM16 Say a 16-bit unsigned number using RESROM digits	;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      16-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_SAYNUM16						  ;;
;;      R0      Number to "speak"					   ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;									  ;;
;;  DESCRIPTION							     ;;
;;      "Says" a 16-bit number using IV_PLAYW to queue up the phrase.       ;;
;;      Because the number may be built from several segments, it could     ;;
;;      easily eat up the queue.  I believe the longest number will take    ;;
;;      7 queue entries -- that is, fill the queue.  Thus, this code	;;
;;      could block, waiting for slots in the queue.			;;
;; ======================================================================== ;;

IV_SAYNUM16 PROC
	    PSHR    R5

	    TSTR    R0
	    BEQ     @@zero	  ; Special case:  Just say "zero"

	    ;; ------------------------------------------------------------ ;;
	    ;;  First, try to pull off 'thousands'.  We call ourselves      ;;
	    ;;  recursively to play the the number of thousands.	    ;;
	    ;; ------------------------------------------------------------ ;;
	    CLRR    R1
@@thloop:   INCR    R1
	    SUBI    #1000,  R0
	    BC      @@thloop

	    ADDI    #1000,  R0
	    PSHR    R0
	    DECR    R1
	    BEQ     @@no_thousand

	    CALL    IV_SAYNUM16.recurse

	    CALL    IV_PLAYW
	    DECLE   36  ; THOUSAND
	    
@@no_thousand
	    PULR    R1

	    ;; ------------------------------------------------------------ ;;
	    ;;  Now try to play hundreds.				   ;;
	    ;; ------------------------------------------------------------ ;;
	    MVII    #7-1, R0    ; ZERO
	    CMPI    #100,   R1
	    BNC     @@no_hundred

@@hloop:    INCR    R0
	    SUBI    #100,   R1
	    BC      @@hloop
	    ADDI    #100,   R1

	    PSHR    R1

	    CALL    IV_PLAYW.1

	    CALL    IV_PLAYW
	    DECLE   35  ; HUNDRED

	    PULR    R1
	    B       @@notrecurse    ; skip "PSHR R5"
@@recurse:  PSHR    R5	      ; recursive entry point for 'thousand'

@@no_hundred:
@@notrecurse:
	    MOVR    R1,     R0
	    BEQ     @@leave

	    SUBI    #20,    R1
	    BNC     @@teens

	    MVII    #27-1, R0   ; TWENTY
@@tyloop    INCR    R0
	    SUBI    #10,    R1
	    BC      @@tyloop
	    ADDI    #10,    R1

	    PSHR    R1
	    CALL    IV_PLAYW.1

	    PULR    R0
	    TSTR    R0
	    BEQ     @@leave

@@teens:
@@zero:     ADDI    #7, R0  ; ZERO

	    CALL    IV_PLAYW.1

@@leave     PULR    PC
	    ENDP

;; ======================================================================== ;;
;;  End of File:  saynum16.asm					      ;;
;; ======================================================================== ;;

IV_INIT_and_wait:     EQU IV_INIT

    ELSE

IV_INIT_and_wait:     EQU _wait	; No voice init; just WAIT.

    ENDI

	IF DEFINED intybasic_flash

;; ======================================================================== ;;
;;  JLP "Save Game" support						 ;;
;; ======================================================================== ;;
JF.first    EQU     $8023
JF.last     EQU     $8024
JF.addr     EQU     $8025
JF.row      EQU     $8026
		   
JF.wrcmd    EQU     $802D
JF.rdcmd    EQU     $802E
JF.ercmd    EQU     $802F
JF.wrkey    EQU     $C0DE
JF.rdkey    EQU     $DEC0
JF.erkey    EQU     $BEEF

JF.write:   DECLE   JF.wrcmd,   JF.wrkey    ; Copy JLP RAM to flash row  
JF.read:    DECLE   JF.rdcmd,   JF.rdkey    ; Copy flash row to JLP RAM  
JF.erase:   DECLE   JF.ercmd,   JF.erkey    ; Erase flash sector 

;; ======================================================================== ;;
;;  JF.INIT	 Copy JLP save-game support routine to System RAM	;;
;; ======================================================================== ;;
JF.INIT     PROC
	    PSHR    R5	    
	    MVII    #@@__code,  R5
	    MVII    #JF.SYSRAM, R4
	    REPEAT  5       
	    MVI@    R5,	 R0      ; \_ Copy code fragment to System RAM
	    MVO@    R0,	 R4      ; /
	    ENDR
	    PULR    PC

	    ;; === start of code that will run from RAM
@@__code:   MVO@    R0,	 R1      ; JF.SYSRAM + 0: initiate command
	    ADD@    R1,	 PC      ; JF.SYSRAM + 1: Wait for JLP to return
	    JR      R5		  ; JF.SYSRAM + 2:
	    MVO@    R2,	 R2      ; JF.SYSRAM + 3: \__ simple ISR
	    JR      R5		  ; JF.SYSRAM + 4: /
	    ;; === end of code that will run from RAM
	    ENDP

;; ======================================================================== ;;
;;  JF.CMD	  Issue a JLP Flash command			       ;;
;;									  ;;
;;  INPUT								   ;;
;;      R0  Slot number to operate on				       ;;
;;      R1  Address to copy to/from in JLP RAM			      ;;
;;      @R5 Command to invoke:					      ;;
;;									  ;;
;;	      JF.write -- Copy JLP RAM to Flash			   ;;
;;	      JF.read  -- Copy Flash to JLP RAM			   ;;
;;	      JF.erase -- Erase flash sector			      ;;
;;									  ;;
;;  OUTPUT								  ;;
;;      R0 - R4 not modified.  (Saved and restored across call)	     ;;
;;      JLP command executed						;;
;;									  ;;
;;  NOTES								   ;;
;;      This code requires two short routines in the console's System RAM.  ;;
;;      It also requires that the system stack reside in System RAM.	;;
;;      Because an interrupt may occur during the code's execution, there   ;;
;;      must be sufficient stack space to service the interrupt (8 words).  ;;
;;									  ;;
;;      The code also relies on the fact that the EXEC ISR dispatch does    ;;
;;      not modify R2.  This allows us to initialize R2 for the ISR ahead   ;;
;;      of time, rather than in the ISR.				    ;;
;; ======================================================================== ;;
JF.CMD      PROC

	    MVO     R4,	 JF.SV.R4    ; \
	    MVII    #JF.SV.R0,  R4	  ;  |
	    MVO@    R0,	 R4	  ;  |- Save registers, but not on
	    MVO@    R1,	 R4	  ;  |  the stack.  (limit stack use)
	    MVO@    R2,	 R4	  ; /

	    MVI@    R5,	 R4	  ; Get command to invoke

	    MVO     R5,	 JF.SV.R5    ; save return address

	    DIS
	    MVO     R1,	 JF.addr     ; \_ Save SG arguments in JLP
	    MVO     R0,	 JF.row      ; /
					  
	    MVI@    R4,	 R1	  ; Get command address
	    MVI@    R4,	 R0	  ; Get unlock word
					  
	    MVII    #$100,      R4	  ; \
	    SDBD			    ;  |_ Save old ISR in save area
	    MVI@    R4,	 R2	  ;  |
	    MVO     R2,	 JF.SV.ISR   ; /
					  
	    MVII    #JF.SYSRAM + 3, R2      ; \
	    MVO     R2,	 $100	;  |_ Set up new ISR in RAM
	    SWAP    R2		      ;  |
	    MVO     R2,	 $101	; / 
					  
	    MVII    #$20,       R2	  ; Address of STIC handshake
	    JSRE    R5,  JF.SYSRAM	  ; Invoke the command
					  
	    MVI     JF.SV.ISR,  R2	  ; \
	    MVO     R2,	 $100	;  |_ Restore old ISR 
	    SWAP    R2		      ;  |
	    MVO     R2,	 $101	; /
					  
	    MVII    #JF.SV.R0,  R5	  ; \
	    MVI@    R5,	 R0	  ;  |
	    MVI@    R5,	 R1	  ;  |- Restore registers
	    MVI@    R5,	 R2	  ;  |
	    MVI@    R5,	 R4	  ; /
	    MVI@    R5,	 PC	  ; Return

	    ENDP


	ENDI

	IF DEFINED intybasic_fastmult

; Quarter Square Multiplication
; Assembly code by Joe Zbiciak, 2015
; Released to public domain.

QSQR8_TBL:  PROC
	    DECLE   $3F80, $3F01, $3E82, $3E04, $3D86, $3D09, $3C8C, $3C10
	    DECLE   $3B94, $3B19, $3A9E, $3A24, $39AA, $3931, $38B8, $3840
	    DECLE   $37C8, $3751, $36DA, $3664, $35EE, $3579, $3504, $3490
	    DECLE   $341C, $33A9, $3336, $32C4, $3252, $31E1, $3170, $3100
	    DECLE   $3090, $3021, $2FB2, $2F44, $2ED6, $2E69, $2DFC, $2D90
	    DECLE   $2D24, $2CB9, $2C4E, $2BE4, $2B7A, $2B11, $2AA8, $2A40
	    DECLE   $29D8, $2971, $290A, $28A4, $283E, $27D9, $2774, $2710
	    DECLE   $26AC, $2649, $25E6, $2584, $2522, $24C1, $2460, $2400
	    DECLE   $23A0, $2341, $22E2, $2284, $2226, $21C9, $216C, $2110
	    DECLE   $20B4, $2059, $1FFE, $1FA4, $1F4A, $1EF1, $1E98, $1E40
	    DECLE   $1DE8, $1D91, $1D3A, $1CE4, $1C8E, $1C39, $1BE4, $1B90
	    DECLE   $1B3C, $1AE9, $1A96, $1A44, $19F2, $19A1, $1950, $1900
	    DECLE   $18B0, $1861, $1812, $17C4, $1776, $1729, $16DC, $1690
	    DECLE   $1644, $15F9, $15AE, $1564, $151A, $14D1, $1488, $1440
	    DECLE   $13F8, $13B1, $136A, $1324, $12DE, $1299, $1254, $1210
	    DECLE   $11CC, $1189, $1146, $1104, $10C2, $1081, $1040, $1000
	    DECLE   $0FC0, $0F81, $0F42, $0F04, $0EC6, $0E89, $0E4C, $0E10
	    DECLE   $0DD4, $0D99, $0D5E, $0D24, $0CEA, $0CB1, $0C78, $0C40
	    DECLE   $0C08, $0BD1, $0B9A, $0B64, $0B2E, $0AF9, $0AC4, $0A90
	    DECLE   $0A5C, $0A29, $09F6, $09C4, $0992, $0961, $0930, $0900
	    DECLE   $08D0, $08A1, $0872, $0844, $0816, $07E9, $07BC, $0790
	    DECLE   $0764, $0739, $070E, $06E4, $06BA, $0691, $0668, $0640
	    DECLE   $0618, $05F1, $05CA, $05A4, $057E, $0559, $0534, $0510
	    DECLE   $04EC, $04C9, $04A6, $0484, $0462, $0441, $0420, $0400
	    DECLE   $03E0, $03C1, $03A2, $0384, $0366, $0349, $032C, $0310
	    DECLE   $02F4, $02D9, $02BE, $02A4, $028A, $0271, $0258, $0240
	    DECLE   $0228, $0211, $01FA, $01E4, $01CE, $01B9, $01A4, $0190
	    DECLE   $017C, $0169, $0156, $0144, $0132, $0121, $0110, $0100
	    DECLE   $00F0, $00E1, $00D2, $00C4, $00B6, $00A9, $009C, $0090
	    DECLE   $0084, $0079, $006E, $0064, $005A, $0051, $0048, $0040
	    DECLE   $0038, $0031, $002A, $0024, $001E, $0019, $0014, $0010
	    DECLE   $000C, $0009, $0006, $0004, $0002, $0001, $0000
@@mid:
	    DECLE   $0000, $0000, $0001, $0002, $0004, $0006, $0009, $000C
	    DECLE   $0010, $0014, $0019, $001E, $0024, $002A, $0031, $0038
	    DECLE   $0040, $0048, $0051, $005A, $0064, $006E, $0079, $0084
	    DECLE   $0090, $009C, $00A9, $00B6, $00C4, $00D2, $00E1, $00F0
	    DECLE   $0100, $0110, $0121, $0132, $0144, $0156, $0169, $017C
	    DECLE   $0190, $01A4, $01B9, $01CE, $01E4, $01FA, $0211, $0228
	    DECLE   $0240, $0258, $0271, $028A, $02A4, $02BE, $02D9, $02F4
	    DECLE   $0310, $032C, $0349, $0366, $0384, $03A2, $03C1, $03E0
	    DECLE   $0400, $0420, $0441, $0462, $0484, $04A6, $04C9, $04EC
	    DECLE   $0510, $0534, $0559, $057E, $05A4, $05CA, $05F1, $0618
	    DECLE   $0640, $0668, $0691, $06BA, $06E4, $070E, $0739, $0764
	    DECLE   $0790, $07BC, $07E9, $0816, $0844, $0872, $08A1, $08D0
	    DECLE   $0900, $0930, $0961, $0992, $09C4, $09F6, $0A29, $0A5C
	    DECLE   $0A90, $0AC4, $0AF9, $0B2E, $0B64, $0B9A, $0BD1, $0C08
	    DECLE   $0C40, $0C78, $0CB1, $0CEA, $0D24, $0D5E, $0D99, $0DD4
	    DECLE   $0E10, $0E4C, $0E89, $0EC6, $0F04, $0F42, $0F81, $0FC0
	    DECLE   $1000, $1040, $1081, $10C2, $1104, $1146, $1189, $11CC
	    DECLE   $1210, $1254, $1299, $12DE, $1324, $136A, $13B1, $13F8
	    DECLE   $1440, $1488, $14D1, $151A, $1564, $15AE, $15F9, $1644
	    DECLE   $1690, $16DC, $1729, $1776, $17C4, $1812, $1861, $18B0
	    DECLE   $1900, $1950, $19A1, $19F2, $1A44, $1A96, $1AE9, $1B3C
	    DECLE   $1B90, $1BE4, $1C39, $1C8E, $1CE4, $1D3A, $1D91, $1DE8
	    DECLE   $1E40, $1E98, $1EF1, $1F4A, $1FA4, $1FFE, $2059, $20B4
	    DECLE   $2110, $216C, $21C9, $2226, $2284, $22E2, $2341, $23A0
	    DECLE   $2400, $2460, $24C1, $2522, $2584, $25E6, $2649, $26AC
	    DECLE   $2710, $2774, $27D9, $283E, $28A4, $290A, $2971, $29D8
	    DECLE   $2A40, $2AA8, $2B11, $2B7A, $2BE4, $2C4E, $2CB9, $2D24
	    DECLE   $2D90, $2DFC, $2E69, $2ED6, $2F44, $2FB2, $3021, $3090
	    DECLE   $3100, $3170, $31E1, $3252, $32C4, $3336, $33A9, $341C
	    DECLE   $3490, $3504, $3579, $35EE, $3664, $36DA, $3751, $37C8
	    DECLE   $3840, $38B8, $3931, $39AA, $3A24, $3A9E, $3B19, $3B94
	    DECLE   $3C10, $3C8C, $3D09, $3D86, $3E04, $3E82, $3F01, $3F80
	    DECLE   $4000, $4080, $4101, $4182, $4204, $4286, $4309, $438C
	    DECLE   $4410, $4494, $4519, $459E, $4624, $46AA, $4731, $47B8
	    DECLE   $4840, $48C8, $4951, $49DA, $4A64, $4AEE, $4B79, $4C04
	    DECLE   $4C90, $4D1C, $4DA9, $4E36, $4EC4, $4F52, $4FE1, $5070
	    DECLE   $5100, $5190, $5221, $52B2, $5344, $53D6, $5469, $54FC
	    DECLE   $5590, $5624, $56B9, $574E, $57E4, $587A, $5911, $59A8
	    DECLE   $5A40, $5AD8, $5B71, $5C0A, $5CA4, $5D3E, $5DD9, $5E74
	    DECLE   $5F10, $5FAC, $6049, $60E6, $6184, $6222, $62C1, $6360
	    DECLE   $6400, $64A0, $6541, $65E2, $6684, $6726, $67C9, $686C
	    DECLE   $6910, $69B4, $6A59, $6AFE, $6BA4, $6C4A, $6CF1, $6D98
	    DECLE   $6E40, $6EE8, $6F91, $703A, $70E4, $718E, $7239, $72E4
	    DECLE   $7390, $743C, $74E9, $7596, $7644, $76F2, $77A1, $7850
	    DECLE   $7900, $79B0, $7A61, $7B12, $7BC4, $7C76, $7D29, $7DDC
	    DECLE   $7E90, $7F44, $7FF9, $80AE, $8164, $821A, $82D1, $8388
	    DECLE   $8440, $84F8, $85B1, $866A, $8724, $87DE, $8899, $8954
	    DECLE   $8A10, $8ACC, $8B89, $8C46, $8D04, $8DC2, $8E81, $8F40
	    DECLE   $9000, $90C0, $9181, $9242, $9304, $93C6, $9489, $954C
	    DECLE   $9610, $96D4, $9799, $985E, $9924, $99EA, $9AB1, $9B78
	    DECLE   $9C40, $9D08, $9DD1, $9E9A, $9F64, $A02E, $A0F9, $A1C4
	    DECLE   $A290, $A35C, $A429, $A4F6, $A5C4, $A692, $A761, $A830
	    DECLE   $A900, $A9D0, $AAA1, $AB72, $AC44, $AD16, $ADE9, $AEBC
	    DECLE   $AF90, $B064, $B139, $B20E, $B2E4, $B3BA, $B491, $B568
	    DECLE   $B640, $B718, $B7F1, $B8CA, $B9A4, $BA7E, $BB59, $BC34
	    DECLE   $BD10, $BDEC, $BEC9, $BFA6, $C084, $C162, $C241, $C320
	    DECLE   $C400, $C4E0, $C5C1, $C6A2, $C784, $C866, $C949, $CA2C
	    DECLE   $CB10, $CBF4, $CCD9, $CDBE, $CEA4, $CF8A, $D071, $D158
	    DECLE   $D240, $D328, $D411, $D4FA, $D5E4, $D6CE, $D7B9, $D8A4
	    DECLE   $D990, $DA7C, $DB69, $DC56, $DD44, $DE32, $DF21, $E010
	    DECLE   $E100, $E1F0, $E2E1, $E3D2, $E4C4, $E5B6, $E6A9, $E79C
	    DECLE   $E890, $E984, $EA79, $EB6E, $EC64, $ED5A, $EE51, $EF48
	    DECLE   $F040, $F138, $F231, $F32A, $F424, $F51E, $F619, $F714
	    DECLE   $F810, $F90C, $FA09, $FB06, $FC04, $FD02, $FE01
	    ENDP

; R0 = R0 * R1, where R0 and R1 are unsigned 8-bit values
; Destroys R1, R4
qs_mpy8:    PROC
	    MOVR    R0,	     R4      ;   6
	    ADDI    #QSQR8_TBL.mid, R1      ;   8
	    ADDR    R1,	     R4      ;   6   a + b
	    SUBR    R0,	     R1      ;   6   a - b
@@ok:       MVI@    R4,	     R0      ;   8
	    SUB@    R1,	     R0      ;   8
	    JR      R5		      ;   7
					    ;----
					    ;  49
	    ENDP
	    

; R1 = R0 * R1, where R0 and R1 are 16-bit values
; destroys R0, R2, R3, R4, R5
qs_mpy16:   PROC
	    PSHR    R5		  ;   9
				   
	    ; Unpack lo/hi
	    MOVR    R0,	 R2      ;   6   
	    ANDI    #$FF,       R0      ;   8   R0 is lo(a)
	    XORR    R0,	 R2      ;   6   
	    SWAP    R2		  ;   6   R2 is hi(a)

	    MOVR    R1,	 R3      ;   6   R3 is orig 16-bit b
	    ANDI    #$FF,       R1      ;   8   R1 is lo(b)
	    MOVR    R1,	 R5      ;   6   R5 is lo(b)
	    XORR    R1,	 R3      ;   6   
	    SWAP    R3		  ;   6   R3 is hi(b)
					;----
					;  67
					
	    ; lo * lo		   
	    MOVR    R0,	 R4      ;   6   R4 is lo(a)
	    ADDI    #QSQR8_TBL.mid, R1  ;   8
	    ADDR    R1,	 R4      ;   6   R4 = lo(a) + lo(b)
	    SUBR    R0,	 R1      ;   6   R1 = lo(a) - lo(b)
					
@@pos_ll:   MVI@    R4,	 R4      ;   8   R4 = qstbl[lo(a)+lo(b)]
	    SUB@    R1,	 R4      ;   8   R4 = lo(a)*lo(b)
					;----
					;  42
					;  67 (carried forward)
					;----
					; 109
				       
	    ; lo * hi		  
	    MOVR    R0,	 R1      ;   6   R0 = R1 = lo(a)
	    ADDI    #QSQR8_TBL.mid, R3  ;   8
	    ADDR    R3,	 R1      ;   6   R1 = hi(b) + lo(a)
	    SUBR    R0,	 R3      ;   6   R3 = hi(b) - lo(a)
				       
@@pos_lh:   MVI@    R1,	 R1      ;   8   R1 = qstbl[hi(b)-lo(a)]
	    SUB@    R3,	 R1      ;   8   R1 = lo(a)*hi(b)
					;----
					;  42
					; 109 (carried forward)
					;----
					; 151
				       
	    ; hi * lo		  
	    MOVR    R5,	 R0      ;   6   R5 = R0 = lo(b)
	    ADDI    #QSQR8_TBL.mid, R2  ;   8
	    ADDR    R2,	 R5      ;   6   R3 = hi(a) + lo(b)
	    SUBR    R0,	 R2      ;   6   R2 = hi(a) - lo(b)
				       
@@pos_hl:   ADD@    R5,	 R1      ;   8   \_ R1 = lo(a)*hi(b)+hi(a)*lo(b)
	    SUB@    R2,	 R1      ;   8   /
					;----
					;  42
					; 151 (carried forward)
					;----
					; 193
				       
	    SWAP    R1		  ;   6   \_ shift upper product left 8
	    ANDI    #$FF00,     R1      ;   8   /
	    ADDR    R4,	 R1      ;   6   final product
	    PULR    PC		  ;  12
					;----
					;  32
					; 193 (carried forward)
					;----
					; 225
	    ENDP

	ENDI

	IF DEFINED intybasic_fastdiv

; Fast unsigned division/remainder
; Assembly code by Oscar Toledo G. Jul/10/2015
; Released to public domain.

	; Ultrafast unsigned division/remainder operation
	; Entry: R0 = Dividend
	;	R1 = Divisor
	; Output: R0 = Quotient
	;	 R2 = Remainder
	; Worst case: 6 + 6 + 9 + 496 = 517 cycles
	; Best case: 6 + (6 + 7) * 16 = 214 cycles

uf_udiv16:	PROC
	CLRR R2		; 6
	SLLC R0,1	; 6
	BC @@1		; 7/9
	SLLC R0,1	; 6
	BC @@2		; 7/9
	SLLC R0,1	; 6
	BC @@3		; 7/9
	SLLC R0,1	; 6
	BC @@4		; 7/9
	SLLC R0,1	; 6
	BC @@5		; 7/9
	SLLC R0,1	; 6
	BC @@6		; 7/9
	SLLC R0,1	; 6
	BC @@7		; 7/9
	SLLC R0,1	; 6
	BC @@8		; 7/9
	SLLC R0,1	; 6
	BC @@9		; 7/9
	SLLC R0,1	; 6
	BC @@10		; 7/9
	SLLC R0,1	; 6
	BC @@11		; 7/9
	SLLC R0,1	; 6
	BC @@12		; 7/9
	SLLC R0,1	; 6
	BC @@13		; 7/9
	SLLC R0,1	; 6
	BC @@14		; 7/9
	SLLC R0,1	; 6
	BC @@15		; 7/9
	SLLC R0,1	; 6
	BC @@16		; 7/9
	JR R5

@@1:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@2:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@3:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@4:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@5:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@6:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@7:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@8:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@9:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@10:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@11:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@12:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@13:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@14:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@15:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@16:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
	JR R5
	
	ENDP

	ENDI

	IF DEFINED intybasic_ecs
	ORG $4800	; Available up to $4FFF

	; Disable ECS ROMs so that they don't conflict with us
	MVII    #$2A5F, R0
	MVO     R0,     $2FFF
	MVII    #$7A5F, R0
	MVO     R0,     $7FFF
	MVII    #$EA5F, R0
	MVO     R0,     $EFFF

	B       $1041       ; resume boot

	ENDI

	ORG $200,$200,"-RWB"

Q2:	; Reserved label for #BACKTAB

	ORG $319,$319,"-RWB"
	;
	; 16-bits variables
	; Note IntyBASIC variables grow up starting in $308.
	;
	IF DEFINED intybasic_voice
IV.Q:      RMB 8    ; IV_xxx	16-bit	  Voice queue  (8 words)
IV.FPTR:   RMB 1    ; IV_xxx	16-bit	  Current FIFO ptr.
IV.PPTR:   RMB 1    ; IV_xxx	16-bit	  Current Phrase ptr.
	ENDI

	ORG $323,$323,"-RWB"

_scroll_buffer: RMB 20  ; Sometimes this is unused
_music_gosub:	RMB 1	; GOSUB pointer
_music_table:	RMB 1	; Note table
_music_p:	RMB 1	; Pointer to music
_frame:	 RMB 1   ; Current frame
_read:	  RMB 1   ; Pointer to DATA
_gram_bitmap:   RMB 1   ; Bitmap for definition
_gram2_bitmap:  RMB 1   ; Secondary bitmap for definition
_screen:    RMB 1       ; Pointer to current screen position
_color:     RMB 1       ; Current color

_col0:      RMB 1       ; Collision status for MOB0
_col1:      RMB 1       ; Collision status for MOB1
_col2:      RMB 1       ; Collision status for MOB2
_col3:      RMB 1       ; Collision status for MOB3
_col4:      RMB 1       ; Collision status for MOB4
_col5:      RMB 1       ; Collision status for MOB5
_col6:      RMB 1       ; Collision status for MOB6
_col7:      RMB 1       ; Collision status for MOB7

Q1:			; Reserved label for #MOBSHADOW
_mobs:      RMB 3*8     ; MOB buffer

SCRATCH:    ORG $100,$100,"-RWBN"
	;
	; 8-bits variables
	;
ISRVEC:     RMB 2       ; Pointer to ISR vector (required by Intellivision ROM)
_int:       RMB 1       ; Signals interrupt received
_ntsc:      RMB 1       ; bit 0 = 1=NTSC, 0=PAL. Bit 1 = 1=ECS detected.
_rand:      RMB 1       ; Pseudo-random value
_gram_target:   RMB 1   ; Contains GRAM card number
_gram_total:    RMB 1   ; Contains total GRAM cards for definition
_gram2_target:  RMB 1   ; Contains GRAM card number
_gram2_total:   RMB 1   ; Contains total GRAM cards for definition
_mode_select:   RMB 1   ; Graphics mode selection
_border_color:  RMB 1   ; Border color
_border_mask:   RMB 1   ; Border mask
    IF DEFINED intybasic_keypad
_cnt1_p0:   RMB 1       ; Debouncing 1
_cnt1_p1:   RMB 1       ; Debouncing 2
_cnt1_key:  RMB 1       ; Currently pressed key
_cnt2_p0:   RMB 1       ; Debouncing 1
_cnt2_p1:   RMB 1       ; Debouncing 2
_cnt2_key:  RMB 1       ; Currently pressed key
    ENDI
    IF DEFINED intybasic_scroll
_scroll_x:  RMB 1       ; Scroll X offset
_scroll_y:  RMB 1       ; Scroll Y offset
_scroll_d:  RMB 1       ; Scroll direction
    ENDI
    IF DEFINED intybasic_music
_music_start:	RMB 2	; Start of music

_music_mode: RMB 1      ; Music mode (0= Not using PSG, 2= Simple, 4= Full, add 1 if using noise channel for drums)
_music_frame: RMB 1     ; Music frame (for 50 hz fixed)
_music_tc:  RMB 1       ; Time counter
_music_t:   RMB 1       ; Time base
_music_i1:  RMB 1       ; Instrument 1 
_music_s1:  RMB 1       ; Sample pointer 1
_music_n1:  RMB 1       ; Note 1
_music_i2:  RMB 1       ; Instrument 2
_music_s2:  RMB 1       ; Sample pointer 2
_music_n2:  RMB 1       ; Note 2
_music_i3:  RMB 1       ; Instrument 3
_music_s3:  RMB 1       ; Sample pointer 3
_music_n3:  RMB 1       ; Note 3
_music_s4:  RMB 1       ; Sample pointer 4
_music_n4:  RMB 1       ; Note 4 (really it's drum)

_music_freq10:	RMB 1   ; Low byte frequency A
_music_freq20:	RMB 1   ; Low byte frequency B
_music_freq30:	RMB 1   ; Low byte frequency C
_music_freq11:	RMB 1   ; High byte frequency A
_music_freq21:	RMB 1   ; High byte frequency B
_music_freq31:	RMB 1   ; High byte frequency C
_music_mix:	RMB 1   ; Mixer
_music_noise:	RMB 1   ; Noise
_music_vol1:	RMB 1   ; Volume A
_music_vol2:	RMB 1   ; Volume B
_music_vol3:	RMB 1   ; Volume C
    ENDI
    IF DEFINED intybasic_music_ecs
_music_i5:  RMB 1       ; Instrument 5
_music_s5:  RMB 1       ; Sample pointer 5
_music_n5:  RMB 1       ; Note 5
_music_i6:  RMB 1       ; Instrument 6
_music_s6:  RMB 1       ; Sample pointer 6
_music_n6:  RMB 1       ; Note 6
_music_i7:  RMB 1       ; Instrument 7
_music_s7:  RMB 1       ; Sample pointer 7
_music_n7:  RMB 1       ; Note 7
_music_s8:  RMB 1       ; Sample pointer 8
_music_n8:  RMB 1       ; Note 8 (really it's drum)

_music2_freq10:	RMB 1   ; Low byte frequency A
_music2_freq20:	RMB 1   ; Low byte frequency B
_music2_freq30:	RMB 1   ; Low byte frequency C
_music2_freq11:	RMB 1   ; High byte frequency A
_music2_freq21:	RMB 1   ; High byte frequency B
_music2_freq31:	RMB 1   ; High byte frequency C
_music2_mix:	RMB 1   ; Mixer
_music2_noise:	RMB 1   ; Noise
_music2_vol1:	RMB 1   ; Volume A
_music2_vol2:	RMB 1   ; Volume B
_music2_vol3:	RMB 1   ; Volume C
    ENDI
    IF DEFINED intybasic_music_volume
_music_vol:	RMB 1	; Global music volume
    ENDI
    IF DEFINED intybasic_voice
IV.QH:     RMB 1    ; IV_xxx	8-bit	   Voice queue head
IV.QT:     RMB 1    ; IV_xxx	8-bit	   Voice queue tail
IV.FLEN:   RMB 1    ; IV_xxx	8-bit	   Length of FIFO data
    ENDI


var_A:	RMB 1	; A
var_C:	RMB 1	; C
var_DIRECTION:	RMB 1	; DIRECTION
var_RESULT:	RMB 1	; RESULT
var_ROOM:	RMB 1	; ROOM
var_TIMER:	RMB 1	; TIMER
var_X:	RMB 1	; X
var_X1:	RMB 1	; X1
var_X2:	RMB 1	; X2
var_X3:	RMB 1	; X3
var_X4:	RMB 1	; X4
var_X5:	RMB 1	; X5
var_Y:	RMB 1	; Y
var_Y1:	RMB 1	; Y1
var_Y1ZOOMY1:	RMB 1	; Y1ZOOMY1
var_Y2:	RMB 1	; Y2
var_Y3:	RMB 1	; Y3
var_Y4:	RMB 1	; Y4
var_Y5:	RMB 1	; Y5
var_ZOOMY1:	RMB 1	; ZOOMY1
_SCRATCH:	EQU $

SYSTEM:	ORG $2F0, $2F0, "-RWBN"
STACK:	RMB 24
var_&C:	RMB 1	; #C
var_&LINE:	RMB 1	; #LINE
var_&MONSTER:	RMB 1	; #MONSTER
var_&SCORE:	RMB 1	; #SCORE
_SYSTEM:	EQU $
