org 0
cpu 8086
;cpu 186

db "SG"
dw end_f-start_f
dw 0
dw codeSeg

start_f:

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

mov byte [toggle], 0
call spawn_new_piece

mov ax, datSeg
mov ds, ax

sti


hltloop:

jmp hltloop

nop
nop

spawn_new_piece:



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
ret

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

push ds

mov cx, datSeg
mov ds, cx


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
mov word cs:[bx], 0x0000 ;"CLEAR" row effect 


push cx
push ax
push dx
push es
push bx
call draw_playfield

mov byte cs:[in_vsync], 2

sti

mov cx, 5000
call sleep

cli
mov byte cs:[in_vsync], 1

pop bx
pop es
pop dx
pop ax
pop cx 

mov word cs:[bx], 0xffff ;"CLEAR" row (last 6 bits set for wall detection) 



push cx
push ax
push dx
push es
push bx
call draw_playfield

mov byte cs:[in_vsync], 2
sti

mov cx, 5000
call sleep

cli
mov byte cs:[in_vsync],1

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

call spawn_new_piece

mov byte cs:[in_vsync], 2
sti

mov cx, 3333
call sleep

cli
mov byte cs:[in_vsync],1


mov byte [keybFlags], 0

pop ds

ret

draw_playfield:
	push ds

	mov bx, fbSeg
	mov ds, bx
	
	mov dx, 0x8000 ;row mask, is 0x8000 because rol first shifts the bit to 0x1

	mov bx, 15 ;byte offset so pixel offset is actually 104, playfield draw offset

	mov cx, 20 ;init cx (y counter)
	
	mov si, playField
	mov di, 40
	cld
	.draw_playfield:
		cs lodsw
	jmp .draw_row
	.no_draw_row:
		push ax
		call clear
		pop ax
	.no_draw_row_no_clear:
		inc bx
	.draw_row:
		rol dx, 1
		
		test dh, 1024 >> 8
		jnz .draw_row_end

		test ax, dx
		jz SHORT .no_draw_row
		test byte [bx], 0xff
		jnz .no_draw_row_no_clear
		mov ch, 189
		
		mov BYTE [bx], 0xff
		add bx, di
		mov BYTE [bx], 0xff
		add bx, di
		
		mov BYTE [bx], 129
		add bx, di
		mov BYTE [bx], 129
		add bx, di
		
		mov BYTE [bx], ch
		add bx, di
		mov BYTE [bx], ch
		add bx, di
		
		mov BYTE [bx], ch
		add bx, di
		mov BYTE [bx], ch
		add bx, di
		
		mov BYTE [bx], ch
		add bx, di
		mov BYTE [bx], ch
		add bx, di
		
		mov BYTE [bx], ch
		add bx, di
		mov BYTE [bx], ch
		add bx, di
		
		mov BYTE [bx], 129
		add bx, di
		mov BYTE [bx], 129
		add bx, di
		
		mov BYTE [bx], 0xff
		add bx, di
		mov BYTE [bx], 0xff
		sub bx, 559+40 ; 6.975 rows offset (next block)
		jmp .draw_row
	.draw_row_end:

	
	;add si, 2
	add bx, 40 * 16 - 10 ; next block row 
	mov dx, 0x8000
	xor ch, ch
	loop .draw_playfield
	.end_loop:
	pop ds
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
shl si, 1
shl si, 1
shl si, 1
shl si, 1
and si, 7 << 4
add si, pieces-1
add si, bp
add si, cx
lodsb
xor ah,ah

mov si, cx
mov cx, [currBlkX]
and cx, 0x1f
rol ax, cl
mov cx, si

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
shl si, 1
shl si, 1
shl si, 1
shl si, 1

and si, 7 << 4
add si, pieces-1
add si, [currOr]
add si, cx
lodsb

xor ah,ah

mov bp,cx

and dh, 0x1f
mov cl, dh
rol ax, cl
mov cx,bp

test ax, bx
loopz .loop

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
shl si, 1
shl si, 1
shl si, 1
shl si, 1

and si, 7 << 4
add si, pieces-1
add si, [currOr]
add si, cx
lodsb

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
		
		test byte [bx], 0xff
		jnz .do_clear
		ret
		.do_clear:
		mov di, 40
		xor al, al
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		
		mov byte [bx], al
		add bx, di
		mov byte [bx], al
		
		sub bx, 559+41 ; 6.975 rows offset (next block)	
		ret

;variable address definitions
;datSeg equ 0x100

playField times 40 db 0 ;CHAR[2*20=40] EACH 2 BYTES REPRESENT A ROW. TETRIS HAS 16 COLUMNS
playFieldEnd dw 0 ;SHORT, end of playfield, please set to all ones
currBlkX dw 0
currBlkY dw 0

frameCount dw 0 ;WORD
keybFlags db 0  ;CHAR:  E0SENT, F0SENT, UP,DOWN,LEFT,RIGHT,R,PAUSE
toggle db 0
skip_draw dw 0
music_pointer dw 0

;currY equ 0x30
currType db 0
currOr dw 0
linesClearCalc db 0 ;CHAR, lines cleared at once
linesClear dw 0 ; SHORT, total lines dcleared
currLevel db 0 ; CHAR, current level 
currScore dw 0 ; SHORT, total score
xTimerOff db 0 ; CHAR for better horizontal controls
gameFlags db 0 ; () () () () () pause x_repeat speedup
dootCounter db 0 ; char, for doot
db 0
in_vsync db 0

iret_vsync:
	iret

vsynctest:



test byte cs:[in_vsync], 1
jnz iret_vsync


push ds
push es
call vgm_step
pop es
pop ds

test byte cs:[in_vsync], 2
jnz iret_vsync

xor BYTE [cs:toggle], 0xff
jnz .no_skip

iret

.no_skip:

push si
push ds
push bx
push es

mov si, cs
mov es, si


.drawgame:

inc BYTE [frameCount]
mov al, [frameCount]

mov ah, [gameFlags]


test BYTE ah, 4 
jz .skip_pause


mov bx, 0x0811
mov si, paused_string
call putstring_xy

jmp .end_doot_cond

.skip_pause:

	

test byte ah, 1
jz .skip_speedup



shl al,1
shl al, 1
.skip_speedup:


mov byte cs:[in_vsync], 1
sti

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

	CALL draw_playfield


	
	mov ax, fbSeg
	mov ds, ax
	
	
	.skip_draw_tick:



	mov bl, cs:[currType]
	and bx, 7
	shl bx, 1
	shl bx, 1
	shl bx, 1
	shl bx, 1

	add bx, pieces
	add bx, cs:[currOr]
	mov si,bx

	
	mov bx, 14 ;substracteed by 1
	add bx, cs:[currBlkX]
	
	
	;multiply by 640
	mov ax, cs:[currBlkY]
	
	mov dx, cx ;backup cx in dx
	
	mov cl, 7
	shl ax, cl
	add bx, ax
	
	shl ax, 1
	shl ax, 1
	add bx,ax
	
	mov cx, dx
	
	
	;mov al,8

	mov dl,0x80

	cs lodsb
	
	mov di,40 
	mov cx, 4 
	


	.no_draw_curr_piece:
	inc bx
	
	
	cld
	.draw_curr_piece:
		rol dl,1				

		test dl,16

		jnz .draw_curr_piece_end
		
		
		test al, dl
		jz SHORT .no_draw_curr_piece
		mov dh, 189
		
		mov BYTE [bx], 0xff
		add bx, di
		mov BYTE [bx], 0xff
		add bx, di
		mov BYTE [bx], 129
		add bx, di
		mov BYTE [bx], 129
		add bx, di
		
		mov BYTE [bx], dh
		add bx, di
		mov BYTE [bx], dh
		add bx, di
		mov BYTE [bx], dh
		add bx, di
		mov BYTE [bx], dh
		add bx, di
		
		mov BYTE [bx], dh
		add bx, di
		mov BYTE [bx], dh
		add bx, di
		mov BYTE [bx], dh
		add bx, di
		mov BYTE [bx], dh
		add bx, di
		
		mov BYTE [bx], 129
		add bx, di
		mov BYTE [bx], 129
		add bx, di
		mov BYTE [bx], 0xff
		add bx, di
		mov BYTE [bx], 0xff
		sub bx, 559+40 ; 6.975 rows offset (next block)
		
		
		jmp .draw_curr_piece

	

	.draw_curr_piece_end:
	cs lodsb
	add bx, 40 * 16 - 4 ; next block row 
	mov dl, 0x80
	loop .draw_curr_piece
	.skip_loop:
	


	.end_doot_cond:
mov ax, datSeg
mov ds, ax
		cli
	
			mov byte CS:[in_vsync], 0
pop es
pop bx
pop ds
pop si
iret



doot:
mov bx, 0xc000
mov ds, bx


mov byte [3], 3
mov byte [2], 0xff

mov byte [3], 0xb
mov byte [2], 0x44

mov byte [3], 0x11
mov byte [2], 0x40

mov bx, datSeg
mov ds, bx

mov BYTE [dootCounter],1

ret

keybTest:
push cx
push ax
push ds

mov ax, 0xc000
mov ds, ax
mov al, [5]


cmp al, 0xf0
jz .skip_iret

cmp al, 0x2e
jbe .skip_iret

pop ds
pop ax
pop cx
iret

.skip_iret:

mov cx, datSeg
mov ds, cx

push dx
push bx
push bp
push si
push di

cmp al, 0xf0
jne .notf0

or BYTE [keybFlags], 0x40

jmp .skip

.notf0:
;and byte [keybFlags], 0xbf

mov bx, controlslookup
xlatb


mov cl, [keybFlags]

.detection:
test cl, 0x40
jnz .unset

or [keybFlags],al


test BYTE al, 1

jz .skip_pause

mov bx, fbSeg
mov ds, bx

mov bx, 8*40*20+15
mov cx, 10
.clear_loop:
call clear
inc bx
loop .clear_loop

mov bx, datSeg
mov ds, bx

xor BYTE [gameFlags], 4
jmp .skip

.skip_pause:

test BYTE al, 00100000b ;no input
jz .skip_orchange

; change rotation and detect if anything collides.

mov bp, [currOr]
add bp, 4
and bp, 15

call detect_coll_or


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

pop di
pop si
pop bp
pop bx
pop dx

pop ds
pop ax
pop cx
iret


controlslookup:
db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0x10, 0x8,0x20,0,0,0,0,0,0x4,0,0,0,0,0,0,0,0,0,0x2
controlslookup_end:

paused_string: db "PAUSED",0

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

%include "iolib.asm"

;%define EFFECTS_SUPPORT
;%define EFFECTS_CHANNEL 3
%include "vgmlib.asm"

music_file:
incbin "tetris.vgm"

align 2
end_f:

db "RN"
dw _start
dw codeSeg
