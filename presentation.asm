org 0
cpu 8086
;cpu 186

db "SG"
dw end_f-start_f
dw 0
dw codeSeg

start_f:


%macro draw_kefrens_loop_contents 0

mov ax, di
mov al, ah

mov cl, 3
sal al, cl


inline_cos_8_preset_bx



mov cl, al
sar cl, 1
sar cl, 1
sub al, cl
sar cl, 1
sub al, cl

cbw

mov cx, ax ;first x

mov ax, di
xchg al, ah
rol ax,1
rol ax, 1

add al,  dl

inline_cos_8_preset_bx

inline_sin_8_preset_bx
cbw
;sar ax, 1

add ax, cx ;modified x

mov cx,ax
sar cx, 1
sar cx, 1
add ax, cx 

sar ax, 1

mov si, ax

mov ax, 0b0011111111111100

mov cx, si
and cl, 0b1111
rol ax, cl

mov cl, 3
sar si, cl 

mov [si+line_buf+320/2/8], ax

add di, 4

mov si, line_buf+4

xor ch, ch
mov cl, 320/8/2-4
rep movsw

add di, 8
mov si, line_buf+4
mov cl, 320/8/2-4
rep movsw
add di, 4

%endmacro

%macro draw_loop_contents 0

	
	mov al, ch

	inline_cos_8_preset_bx
	
	mov ah, al ;x1

	add ch, 64 ;plus 0.25
	mov al, ch ;restore a+0.25
	inline_cos_8_preset_bx

	cmp al,ah ;if x2<x1
	jnl %%.skip
	
	;mov dl, cl
	
	sar ah, 1
	sar al, 1

	mov dx, cx

	mov cl, ah
	cbw
	mov di, ax ;x2
	mov al, cl
	cbw
	mov si, ax
	


	not al
	and al, 0b111
	mov cl, al

	mov ax, 0b0011001111000000

	ror al, cl

	mov cx, di
	and cl, 0b111
	rol ah, cl
	
	mov cl, 3
		
	sar si, cl
	sar di, cl

	mov cx, dx
	
	
	
	mov dx, 0xa000
	mov ss, dx

	add bp, 320/2/8 ;xoff	
	or [si+bp], al 
	or [di+bp], ah
	add bp, 320/8
	or [si+bp], al ;320/2/8 = xoff
	or [di+bp], ah

	sub bp, 320/8+320/2/8	
	mov dx, 0x3000
	mov ss, dx



	
	%%.skip:

%endmacro

	
	

vsync:
	
	push ax
	push es
	push si
	push ds
	
	
	mov ax, [cs:music_pointer]
	test ax, ax
	jz .start_playback
	
	cld ;up
	mov si, ax
	
	
	mov ax, 0xc000
	mov es, ax
		
.loop:

	lodsb
	
	cmp al, 0xbd
	jnz .wait

	lodsw ;get data to write and value
	
	mov [es:3], al;write reg addr
	mov [es:2], ah;write reg data 
	
	lodsb
	
	cmp al, 0xbd
	jnz .wait

	lodsw ;get data to write and value
	
	mov [es:3], al;write reg addr
	mov [es:2], ah;write reg data 
	
	jmp .loop ;process more commands
	
.wait:
	cmp al, 0x62
	jnz .start_playback ; unknown command, restart
 ;1 frame delay, do nothing
 	mov cs:[music_pointer], si ;store it back

	pop ds
	pop si
	pop es
	pop ax
	iret
	
.start_playback:
	mov ax, [music_file+0x34] ;data offset
	add ax, music_file + 0x34;offset relative to stream
	mov cs:[music_pointer], ax ;store into music pointer

	pop ds
	pop si
	pop es
	pop ax
	iret
	
	
welcome_str: db "WELCOME TO THE EAGLE-88 PRESENTATION",10,"THE DEMO WILL BEGIN SHORTLY"
			db 10
			db 10
			db "SYSTEM SPECS:",10
			db "INTEL 80C88/NEC V20 CPU @6.29375 MHZ",10
			db "384KIB STATIC SYSTEM RAM", 10
			db "320x480 MONOCHROME FRAMEBUFFER GRAPHICS WITH 32KIB VRAM",10
			db "16c450 UART (SERIAL INTERFACE CHIP)",10
			db "OPTIONAL SAA1099 SOUND CHIP ADDON",10
			db 10
			db "BUILD TIME: APPROX 4 MONTHES",10
			db "MUSIC: M.U.L.E THEME SAA1099 ARRANGEMENT",10
			db 0			
			
%include "mathlib.asm"

	
start:
	call iolib_setup
	

.reset:
	call clear_screen
	;print stuff here
	mov si, welcome_str
	cli
	call putstring
	
	
	
	mov cx, 65535
	sti
.wait_loop:
	times 20 imul word [99]
	loop .wait_loop
	
	
		mov cx, 320*480/8/2
		mov ax, 0xa000
		mov es, ax
		xor ax, ax
		mov di, ax
	
	

		rep stosw
	
	


		mov word [ticks], 0


	
	
.main_draw_loop:

mov ax, 0xa000
mov es, ax

xor cx, cx

xor bx, bx

mov dx, [ticks]
add word dx, 4


cmp word dx, 30*70
jae reset_demo
cmp word dx, 30*20
mov [ticks], dx
ja .draw_kefrens


	mov ax, 0xa000

	mov es, ax

	mov di, 320/8*480-14
	
	mov bx, (320/8/2)-12

	xor ax, ax

	std

.fast_clear_loop:
	mov cx, bx
	rep stosw
	
	sub di, 24
	mov cx, bx
	rep stosw
	sub di, 24
		
	mov cx, bx
	rep stosw
	sub di, 24

	mov cx, bx
	rep stosw
	sub di, 24


	jns .fast_clear_loop
	
	cld
		


	mov bx, sinetab
	
	mov cl, dl
	mov bp, ax

		xchg bx, bx

.draw_line_loop:
	
	mov ax, bp
	mov al, cl


	add al, ah
	sar al, 1

	inline_cos_8_preset_bx

	mov ah, al
	
	mov al, cl

	inline_sin_8_preset_bx
	 
	add al, ah
	
	inline_cos_8_preset_bx
	
	mov ch, al ;backup a in ch	



.draw_loop:
	cli	
%rep 12
	draw_loop_contents
	
	draw_loop_contents
	
	draw_loop_contents
	
	draw_loop_contents


	add bp, 320/8*2
%endrep

	sti

	cmp bp, 320/8*470
	jb .draw_line_loop
	
	
	
	
				xchg bx, bx


	jmp .main_draw_loop

.draw_kefrens:
add word [ticks], 2

mov ax, datSeg
mov es,ax
mov di, line_buf
mov cx, 320/8/2
mov ax, 0b0000000100000000
rep stosw
mov ax, 0xa000
mov es, ax

xor di, di

mov bx, sinetab

.draw_kefrens_loop:
cli
%rep 12 
	draw_kefrens_loop_contents
%endrep
sti
cmp di, 320/8*480
jb .draw_kefrens_loop



.exit:

	
	
	jmp .main_draw_loop

	

music_pointer: dw 0


reset_demo:
	xor sp, sp
	jmp start.reset



line_buf: times 320/8+9 db 0


y_off dw 0
ticks dw 0


music_file:
incbin "presmuzik.vgm"

%define USE_OWN_VSYNC
%include "iolib.asm"

align 2



end_f:

db "RN"
dw start
dw codeSeg
