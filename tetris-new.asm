org 0x0
cpu 8086
use16

;stack equ 0x500
;fbSeg equ 0xa000

%macro draw_wall_row 1

mov byte [bx], %1
add bx, dx
mov byte [bx], %1
add bx, di
mov byte [bx], %1
add bx, dx
mov byte [bx], %1
add bx, di
%endmacro

;end 8086 compatibility
_start:

cli 

call iolib_setup

xor ax, ax
mov ds, ax

mov bx, vsynctest
mov [4*0], bx
mov bx, keybTest
mov [4*3], bx
mov bx, cs
mov [4*0+2], bx
mov [4*3+2], bx

mov bx, 0xc000
mov es, bx
mov byte [es:7], 0xff
mov byte [es:6], 0

mov bx, fbSeg
mov ds, bx
mov bx, 14
mov cx, 7
mov dx, 11
mov di, 320/8-11
mov ah, 0b11101111

.set_wall_loop:
draw_wall_row ah
draw_wall_row ah
draw_wall_row ah
draw_wall_row 0
mov al, 0b10111101
draw_wall_row al
draw_wall_row al
draw_wall_row al
draw_wall_row 0

mov al, 0b11110111
draw_wall_row al
draw_wall_row al
draw_wall_row al
draw_wall_row 0

mov al, 0b11101111
draw_wall_row ah
draw_wall_row ah
draw_wall_row ah
draw_wall_row 0

mov al, 0b01111011
draw_wall_row al
draw_wall_row al
draw_wall_row al
draw_wall_row 0

mov al, 0b11101111
draw_wall_row ah
draw_wall_row ah
draw_wall_row ah
draw_wall_row 0

dec cx
jz .quit
jmp .set_wall_loop
.quit:
			;init data segment
cld			



mov bx, datSeg
mov ds, bx
mov es, bx




mov cx,0x70
xor ax, ax
xor di,di
rep stosw

mov di,controlslookup_ram
mov si, controlslookup
mov cx, controlslookup_end-controlslookup
mov ax, cs
mov ds, ax
mov ax, datSeg
mov es, ax
rep movsb

mov ds,ax

mov byte [toggle], 0

mov cx, 21
mov ax, 1111110000000000b
mov di, playField
rep stosw 

mov word [playFieldEnd], 0xffff

mov byte [currType], 0x5a

mov bx, 0xc000
mov ds, bx

;sound test
mov BYTE [3], 0x10 ;addr 10
mov BYTE [2], 0x4;octave 3 for channel 0

mov BYTE [3] ,0x14
mov BYTE [2], 1b ; enable channel 0 square

mov BYTE [3], 0x1c
mov BYTE [2], 1 ; sound enable

sti


hltloop:

jmp hltloop

nop
nop

;sleeps for duration CX
sleep:
push ax
push dx

.loopf:



imul ax
imul ax
loop .loopf

pop dx
pop ax

ret

; spawns a new piece. performance requirements are a bit more relaxed heres
reset_tick:


mov cx, 4


.set_playfield:
xor bh,bh
mov bl, [currBlkY]
add bl, cl
shl bl, 1
add bx, playField-2

mov si, [currType]
and si, 7

shl si, 1
shl si, 1
shl si, 1
shl si, 1 

and si, 0xff
add si, pieces-1
add si, [currOr]
add si, cx

mov al, [es:si]
xor ah,ah

mov bp,cx
mov cx, [currBlkX]
and cx, 0xf
rol ax, cl
mov cx,bp

or WORD [bx], ax
loop .set_playfield

mov BYTE [currBlkY],0
mov WORD [currBlkX],0
mov BYTE [currOr], 0
mov BYTE [gameFlags], 0

mov cx, 19
mov BYTE [linesClearCalc], 0


.detect_full_row:
xor bx,bx
add bx, cx
inc bx ; offset cx
shl bx, 1
add bx, playField - 2 ;minus one cus cx is going to be 1 more than the real y val

mov ax, [bx]

xor ax, 0xffff ; if equ then zero aka full row
jnz .skip_clear_row


inc BYTE [linesClearCalc] ;increment for iototal lines cleared point calculation
mov word [bx], 0x0000 ;"CLEAR" row effect 


push cx
push ax
push dx
push es
push bx
call draw_playfield

mov cx, 5000
call sleep

pop bx
pop es
pop dx
pop ax
pop cx 

mov word [bx], 0xffff ;"CLEAR" row (last 6 bits set for wall detection) 



push cx
push ax
push dx
push es
push bx
call draw_playfield

mov cx, 5000
call sleep

pop bx
pop es
pop dx
pop ax
pop cx 

mov word [bx], 1111110000000000b ;"CLEAR" row (last 6 bits set for wall detection) 


push cx
push es

mov bp, datSeg
mov es, bp
;move blocks down 
std ;set direction to DOWNs
mov di, bx ; current row (BLANK)

mov si, bx
sub si, 2     ; upper row
rep movsw  ; mov rows down

pop es
pop cx

inc cx

.skip_clear_row:

loop .detect_full_row

test byte [linesClearCalc], 0xff
jz .new_piece

.add_score:
push cx
mov cl, [linesClearCalc]
mov al, 2
shl al,cl
pop cx

inc al

mov bl, [currLevel]
inc bl
mul bl

xor ah,ah

add [currScore], ax

call debug_chk_var

.new_piece:


;rng algo
.rng_algo:
mov dh, [currType]


xor dl,dl
test dh, 100b
jz .skip_xor1

xor dl, 1

.skip_xor1:

test dh, 1b
jz .skip_xor2

xor dl, 1

.skip_xor2:
shl dh, 1

and dh, 11111110b
or dh, dl

mov [currType], dh
and dh, 0x7

mov BYTE [currOr], 0

mov cx, 3333
call sleep ;delay 

mov byte [keybFlags], 0

ret

draw_playfield:
	

	mov bx, fbSeg
	mov es, bx
	
	mov ax, 0x8000 ;row mask, is 0x8000 because rol first shifts the bit to 0x1

	
	mov bx, 15 ;byte offset so pixel offset is actually 104, playfield draw offset

	mov cx, 20 ;init cx (y counter)
	
	mov si, playField
	.draw_playfield:
	jmp .draw_row
	.no_draw_row:
		call clear
	.draw_row:
		rol ax, 1
		
		test ax, 1024
		
		jz SHORT .go_no_draw_row_end;reached end of row
		jmp .draw_row_end
		.go_no_draw_row_end:
		mov dx, [si]

		test ax, dx
		jz SHORT .no_draw_row
		test byte [es:bx], 0xff
		jz .draw_anyway
		inc bx
		jmp .draw_row
		.draw_anyway:
		 
		mov BYTE [es:bx], 0xff
		add bx, 40
		mov BYTE [es:bx], 0xff
		add bx, 40
		
		mov BYTE [es:bx], 129
		add bx, 40
		mov BYTE [es:bx], 129
		add bx, 40
		
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		
		mov BYTE [es:bx], 129
		add bx, 40
		mov BYTE [es:bx], 129
		add bx, 40
		
		mov BYTE [es:bx], 0xff
		add bx, 40
		mov BYTE [es:bx], 0xff
		sub bx, 559+40 ; 6.975 rows offset (next block)
		jmp .draw_row
	.draw_row_end:

	
	add si, 2
	add bx, 40 * 16 - 10 ; next block row 
	mov ax, 0x8000

	dec cx
	jz .end_loop
	jmp .draw_playfield
	.end_loop:
	ret

; bp = or
detect_coll_or:
push si
push ax
push dx


mov cx,4


mov dl, [currBlkY]
.loop:
xor bx,bx
mov bl, dl
add bl, cl
shl bl, 1
add bx, playField-2

mov bx, [bx]

mov si, [currType]
and si, 7
shl si, 1
shl si, 1
shl si, 1
shl si, 1
and si, 0xff
add si, pieces-1
add si, bp
add si, cx
mov al, [cs:si]

xor ah,ah

push cx
mov cx, [currBlkX]
and cx, 0x1f
rol ax, cl
pop cx

test ax, bx
loopz .loop

pop dx
pop ax
pop si

ret

;checks x collison, DH = x coord
;CX = iscolliding
detect_coll_x:
push si
push ax
push dx
push es


mov cx,4


mov dl, [currBlkY]
.loop:
xor bx,bx
mov bl, dl
add bl, cl
shl bl, 1
add bx, playField-2

mov bx, [bx]

mov si, [currType]
and si, 7
shl si, 1
shl si, 1
shl si, 1
shl si, 1

and si, 0xff
add si, pieces-1
add si, [currOr]
add si, cx
mov al, [cs:si]

xor ah,ah

mov bp,cx

and dh, 0x1f
mov cl, dh
rol ax, cl
mov cx,bp

test ax, bx
loopz .loop

pop es
pop dx
pop ax
pop si

ret

debug_chk_var:
	push es
	
	push ax
	mov ax, 0xc000
	mov es, ax
	pop ax
	mov ax, [keybFlags]
	mov BYTE [es:0], al
	
	pop es
	
	ret



;detects collision of piece and playfield
;DL = piece y
;CX = 0 : no coll
detect_coll:
mov cx,4

.loop:
xor bx,bx
mov bl, dl
add bl, cl
shl bl, 1
add bx, playField-2

mov bx, [bx]


mov si, [currType]
and si, 7
shl si, 1
shl si, 1
shl si, 1
shl si, 1

and si, 0xff
add si, pieces-1
add si, [currOr]
add si, cx
mov al, [es:si]

xor ah,ah

mov bp,cx
mov cx, [currBlkX]
and cx, 0x1f
rol ax, cl
mov cx,bp

test ax, bx
loopz .loop
.preend:

ret




clear:
		test byte [es:bx], 0xff
		jnz .do_clear
		inc bx
		ret
		.do_clear:
		
		mov byte [es:bx], 0x0
		add bx, 40
		
		mov byte [es:bx], 0x0
		add bx, 40
		
		mov byte [es:bx], 0
		add bx, 40
		
		mov byte [es:bx], 0
		add bx, 40
		
		mov byte [es:bx], 0
		add bx, 40
		
		mov byte [es:bx], 0
		add bx, 40
		
		mov byte [es:bx], 0
		add bx, 40
		
		mov byte [es:bx], 0
		add bx, 40
		
		mov BYTE [es:bx], 0
		add bx, 40
		
		mov BYTE [es:bx], 0
		add bx, 40
		
		mov BYTE [es:bx], 0
		add bx, 40
		
		mov BYTE [es:bx], 0
		add bx, 40
		
		mov BYTE [es:bx], 0
		add bx, 40
		
		mov BYTE [es:bx], 0
		add bx, 40
		
		mov BYTE [es:bx], 0
		add bx, 40
		mov BYTE [es:bx], 0
		
		sub bx, 559+40 ; 6.975 rows offset (next block)	
		ret

;variable address definitions
;datSeg equ 0x100
frameCount equ 0x2d ;CHAR
keybFlags equ 0x2e ;CHAR:  E0SENT, F0SENT, UP,DOWN,LEFT,RIGHT,R,PAUSE
currBlkX equ 0x30
;currY equ 0x30
currType equ 0x32
currOr equ 0x34
linesClearCalc equ 0x36 ;CHAR, lines cleared at once
linesClear equ 0x37 ; SHORT, total lines dcleared
currLevel equ 0x39 ; CHAR, current level 
currScore equ 0x40 ; SHORT, total score
xTimerOff equ 0x42 ; CHAR for better horizontal controls
gameFlags equ 0x43 ; () () () () () pause x_repeat speedup
dootCounter equ 0x44 ; char, for doot
currBlkY equ 0x45
controlslookup_ram equ currBlkY+2
is_in_int equ controlslookup_ram+(controlslookup_end-controlslookup)+1
toggle equ is_in_int+2
skip_draw equ toggle + 2
playField equ skip_draw+2 ;CHAR[2*20=40] EACH 2 BYTES REPRESENT A ROW. TETRIS HAS 16 COLUMNS
playFieldEnd equ playField+40 ;SHORT, end of playfield, please set to all ones


vsynctest:


xor BYTE [toggle], 0xff
jnz .no_skip
iret

.no_skip:

push si
push ds
push bx
push es



mov byte [skip_draw], 0

mov si,0xe000
mov es,si



.drawgame:

inc BYTE [frameCount]
mov al, [frameCount]

mov ah, [gameFlags]


test BYTE ah, 4 
jz .skip_pause

jmp .skip_tick_curr

.skip_pause:

test byte ah, 1
jz .skip_speedup



shl al,1
shl al, 1
.skip_speedup:

test byte [frameCount], 1b
jnz .skip_inputtick


test BYTE ah, 10b
jz .allow_key

and BYTE [gameFlags], 0xfd
mov BYTE [xTimerOff], 2
jmp .allow_key2
.allow_key:



test BYTE [xTimerOff], 0xff

jz .allow_key2

dec BYTE [xTimerOff]
jmp .skip_inputtick

.allow_key2:


mov dh, [currBlkX]


test BYTE [keybFlags], 4
jz .skip_left

inc dh
call detect_coll_x
jnz .skip_left
and BYTE [keybFlags], 11110111b

mov [currBlkX], dh

mov dl, 0x11
call doot 

.skip_left:

test BYTE [keybFlags], 8
jz .skip_right


dec dh
call detect_coll_x
jnz .skip_right
and BYTE [keybFlags], 11111011b


mov [currBlkX], dh

mov dl, 0x11
call doot

.skip_right:


test byte [currBlkX], 0x80
jz .nosign

mov byte [currBlkX+1], 0xff
jmp .skip_inputtick

.nosign:
mov byte [currBlkX+1], 0


.skip_inputtick:


mov cx, bp


mov cl, [currLevel]
shr al, cl

test byte al, 111b ; drop speed governor

mov bp, cx

jnz .skip_tick_curr

.skip_skip_pf:

mov bl, [currBlkY]
mov dl,bl
inc dl

call detect_coll

jz .skip_fix_y

jmp .reset_y

.skip_fix_y:
mov [currBlkY], dl
mov bl,dl



jmp .skip_tick_curr
.reset_y:

call reset_tick

.skip_tick_curr:
	

	
	mov byte [is_in_int], 1

	

	CALL draw_playfield
	
	
	
	.skip_draw_tick:


	mov bp, fbSeg
	mov es, bp

	mov bl, [currType]
	and bl, 7
	xor bh,bh
	shl bx, 1
	shl bx, 1
	shl bx, 1
	shl bx, 1

	add bx, pieces
	add bx, [currOr]
	mov si,bx

	
	mov bx, 15
	add bx, [currBlkX]
	
	
	
	mov ax, 40*16
	mul WORD [currBlkY]
	add bx,ax
	

	
	mov cx, 4 
	
	;mov al,8

		push ds
		mov dx, cs
		mov ds, dx
		
		mov dl,0x80


	lodsb
	jmp .draw_curr_piece
	.no_draw_curr_piece:
	inc bx

	.draw_curr_piece:
		rol dl,1				

		test dl,16

		jz SHORT .skip_go_draw_curr_piece_end
		jmp .draw_curr_piece_end
		.skip_go_draw_curr_piece_end:
		
		
		test al, dl
		jz SHORT .no_draw_curr_piece
		
		mov BYTE [es:bx], 0xff
		add bx, 40
		mov BYTE [es:bx], 0xff
		add bx, 40
		mov BYTE [es:bx], 129
		add bx, 40
		mov BYTE [es:bx], 129
		add bx, 40
		
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		mov BYTE [es:bx], 189
		add bx, 40
		
		mov BYTE [es:bx], 129
		add bx, 40
		mov BYTE [es:bx], 129
		add bx, 40
		mov BYTE [es:bx], 0xff
		add bx, 40
		mov BYTE [es:bx], 0xff
		sub bx, 559+40 ; 6.975 rows offset (next block)
		jmp .draw_curr_piece


	.draw_curr_piece_end:
	lodsb
	add bx, 40 * 16 - 4 ; next block row 
	mov dl, 0x80
	dec cx
	jz .skip_loop
	jmp .draw_curr_piece
	.skip_loop:
	
				pop ds


	;sound tick
	.sound_tick:

	test byte [dootCounter],0xff
	jnz .skip_zero_doot
	xor dl,dl
	call doot	
	jmp .end_doot_cond
	.skip_zero_doot:
	dec BYTE [dootCounter]
	
	.end_doot_cond:

pop dx
pop cx
pop di
pop ax


iret



doot:
push ds
mov bx, 0xc000
mov ds, bx


mov byte [3], 0
mov byte [2], dl

mov byte [3], 0x8
mov byte [2], 0x44

mov byte [3], 0x10
mov byte [2], 0x4

pop ds

mov BYTE [dootCounter],1

ret

keybTest:

push cx
push ax

mov cx, 0xc000
mov ds, cx
mov al, [5]

mov cx, datSeg
mov ds, cx

cmp al, 0xf0
jz .skip_iret

cmp al, 0x2e
jbe .skip_iret
pop ax
pop cx
iret

.skip_iret:

push bx
cmp al, 0xf0
jne .notf0

or BYTE [keybFlags], 0x40

jmp .skip

.notf0:
;and byte [keybFlags], 0xbf

mov bx, controlslookup_ram
xlatb


mov cl, [keybFlags]

.detection:
test cl, 0x40
jnz .unset

or [keybFlags],al


test BYTE al, 1

jz .skip_pause

xor BYTE [gameFlags], 4
jmp .skip

.skip_pause:

test BYTE al, 00100000b ;no input
jz .skip_orchange

; change rotation and detect if anything collides.

mov bp, [currOr]
add bp, 4
and bp, 15

mov ax, 0xe000
mov es, ax

call detect_coll_or


mov ax, datSeg
mov es, ax

jnz .skip_orchange ;skip if coll

mov dl, 0x22
call doot


mov [currOr], bp

.skip_orchange:

test al, 10000b

jz .skip_down


or byte [gameFlags], 1b

.skip_down:

test al, 1100b
jz .skip

or BYTE [gameFlags], 10b

jmp .skip

.unset:

not al
and cl, al
and byte cl, 0xbf
mov [keybFlags],cl


test al, 10000b
jnz .skip

and byte [gameFlags], 0xfe

.skip:
mov al, [frameCount]

pop bx

pop ax
pop cx


iret


controlslookup:
db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0x10, 0x8,0x20,0,0,0,0,0,0x4,0,0,0,0,0,0,0,0,0,0x2
controlslookup_end:

pieces:
	null:
	dd 0
	dd 0
	dd 0
	dd 0
	straight: ; N O T E : 4x4, rest 3x3 
		
		.o0:
			db 0000b
			db 1111b
			db 0000b
			db 0000b
		.o1:
			db 0100b
			db 0100b
			db 0100b
			db 0100b
		.o2:
			db 00000000b
			db 00000b
			db 1111b
			db 00000000b
		.o3:
			db 010b
			db 010b
			db 010b
			db 010b
	L: 
		.o0:
			db 001b
			db 111b
			db 00000000b
			db 00000000b
		.o1:	
			db 110b
			db 010b
			db 010b
			db 00000000b
		.o2:
			db 000b
			db 111b
			db 100b
			db 0
		.o3:
			db 010b
			db 010b
			db 011b
			db 0
	invert_L:
		.o0:
			db 100b
			db 111b
			db 00000000b
			db 0
		.o1:
			db 011b
			db 010b
			db 010b
			db 0
		.o2:
			db 00000000b
			db 111b
			db 001b
			db 0
		.o3:
			db 010b
			db 010b
			db 110b
			db 0
	square:
		.o0:
			db 11b
			db 11b
			db 0 
			db 0
		.o1:
			db 11b
			db 11b
			db 0 
			db 0
		.o2:    
			db 11b
			db 11b
			db 0
			db 0
		.o3:
			db 11b
			db 11b
			db 00000000b
	S:		db 0
		.o0:
			db 110b
			db 011b
			db 000b
			db 0
		.o1:
			db 001b
			db 011b
			db 010b
			db 0
		.o2: 	
			db 000b
			db 110b
			db 011b
			db 0
		.o3:
			db 010b
			db 110b
			db 100b
			db 0
	T:
		.o0:
			db 010b
			db 111b
			db 00000000b
			db 0
		.o1: 
			db 010b
			db 110b
			db 010b
			db 0
		.o2:
			db 000b
			db 111b
			db 010b
			db 0
		.o3:
			db 010b
			db 011b
			db 010b
			db 0
	Z:

		.o0:
			db 011b
			db 110b
			db 00000000b
			db 0
		.o1:
			db 010b
			db 011b
			db 001b
			db 0
		.o2:
			db 000b
			db 011b
			db 110b
			db 0
		.o3:
			db 100b
			db 110b
			db 010b
			db 0
%define IN_ROM
%include "iolib.asm"


resb 0x20000 - 0x10- ($-$$) 

jmp 0xe000:0x0


resb 0x20000 - 2 -($-$$)

db 0xca, 0xfe
