org 0x0

use16
cpu 8086 

fbSeg equ 0xa000


serint_enable equ 5 ;byte
sys_params.mem_sz equ 2

currseg_sz equ 6 ; word
currseg_addr equ 8 ; word
currseg_seg equ 10 ;word
music_pointer equ 20 ;word
music_seg equ 22
;end 8086 compatibility
_start:



call iolib_setup
cli
mov ax, 0xc000
mov es, ax
mov byte es:[8+1], 0b; no ints


xor ax, ax
mov es, ax

mov al, 0
xor di,di
mov cx, 0x1000
rep stosb


mov ax, 0x5000
mov ds, ax

cmp word [0x124], 0xB001 ;warm boot detection
jnz short .no_warm_boot
jmp .warm_boot
.no_warm_boot:


mov bx, 0
mov es, bx
mov ds, bx
xor dx, dx


mov al, 27
call putc
mov al, 'c'
call putc

push bx
mov bx, 0x0003
call setcpos
pop bx

mov al, 'K'
call putc
;memory check
.mem_sz_test:


xor bx, bx
.mem_sz_test_64k:
	
	mov word [es:bx], bx; check if write works
	cmp word [es:bx], bx
	jnz .end_of_mem
	mov word [es:bx],0xbaff ;second write attmept
	cmp word [es:bx], 0xbaff
	jnz .end_of_mem
	
	test bx, 0xfff
	jz .print_prog
	
	add bx,2
	jnz .mem_sz_test_64k	
	
	jmp .out
.print_prog:
	push dx
	
	mov al, bh
	mov ah, dh ; seg top 
	shr ah, 1
	shr ah,1 
	shr ah,1
	shr ah,1 ;shiftt it for real addr
	
	shr ax, 1
	shr ax, 1

	
	mov dl, 10
	
	div dl
	

	mov si, ax

	push bx
	mov bx, 2
	call setcpos
	
	mov ax, si
		mov al, ah
	add al, 0x30

	call putc
	
	mov ax, si
	xor ah, ah
	
	div dl
	
	mov si, ax

	
	mov bx, 1
	call setcpos
	
	mov ax, si
		mov al, ah
	add al, 0x30
	call putc
	
	mov ax, si
	xor ah, ah

	div dl
	
	mov si, ax

	xor bx,bx

	call setcpos
	pop bx
	
	mov ax, si
	mov al, ah
	add al, 0x30
	call putc
	
	pop dx
	
	add bx,2
	jnz .mem_sz_test_64k
.out:

add dx, 0x1000
mov es, dx

jnz .mem_sz_test

.end_of_mem:

mov ax, 0x5000
mov ds, ax
mov word [0x124], 0xb001

mov ax, datSeg
mov ds, ax
mov es, ax

mov al, 10
call putc

;extrct memory size /256
mov al, bh
mov ah, dh ; seg top 
mov [sys_params.mem_sz], ax

.warm_boot:

mov bx, codeSeg
mov ds, bx

mov si, vram_str
call putstring

mov bx, 0xa000
mov es, bx ;vram seg
mov ds, bx 
xor si, si 
cld
.vram_fill_zero:
	mov cx, 0x8000 ;half of 32
	xor ax, ax
	xor di, di
	rep stosw
	xor di, di
.vram_fill:
	lodsw 
	test ax, ax
	jnz .vram_exit
	mov ax, di
	not ax
	stosw
	cmp [di-2], ax
	jnz .vram_exit
	test di, 0x7ff
	jnz .vram_fill ;fill addresses
	
	mov al, 13
	call putc
	mov ax, di
	mov al, ah
	xor ah, ah
	shr al, 1
	shr al,1
	call putint_dec
	mov al, 'K'
	call putc
	jmp .vram_fill

.vram_exit:

mov cx, 0x8000
xor ax, ax
rep stosw

mov al, 10
call putc


call sd_cold_init


xor ax, ax
mov es, ax
;install vsync handler
mov word [es:0], vgm_vsync
mov word [es:2], codeSeg

;install vbios funcs
mov word [es:255*4], bios_disp_handler
mov word [es:255*4+2], codeSeg

mov ax, codeSeg
mov ds, ax
mov es, ax
mov si, init_complete
xor bx,bx
int 0xff


mov ax, datSeg
mov ds,ax

mov word [music_pointer], 0 ;zero it

sti


;
cmdloop:
	mov di, currseg_sz; check next packet command
	mov cx, ds
	mov es, cx
	mov cx, 2
	
	call serread 
	cmp word [currseg_sz],'SG' ;are we loading a segment
	jnz .skip_sg
	;read in seg sz, addr, es

	cli
	push ds
	mov ax, codeSeg
	mov ds, ax
	mov si, load_seg_msg
        push bp
	call putstring
	pop bp
	pop ds
	sti
	
	mov di, currseg_sz
	mov cx, 6
	call serread
	add word [currseg_addr], 8; skip header
	mov di, [currseg_addr]
	mov cx, [currseg_sz]
	mov ax, [currseg_seg]

	
	push es
	mov es, ax
	call serread
	pop es
	.skip_sg:
	cmp word [currseg_sz],'RN' ; are we going to run the code
	jnz .skip_en
	cli
	mov al, 10
	call putc
	;read in entry addr and seg
	mov di, currseg_addr
	mov cx, 4
	call serread	



	mov al, 10
	call putc
	xor ax, ax
	xor bx,bx
	xor cx, cx
	xor dx, dx
	xor bp,bp
	xor sp,sp
	mov ds, bp
	mov es, bp
	mov ss, bp

	push bp
	popf 
	
	jmp far [currseg_addr+datSeg*0x10]
	.skip_en:
	jmp cmdloop





serint_serread:
mov byte [8+4],0 

jcxz .skip_int
dec cx

mov al, [8] ;receive from serial
stosb ;registers setup in serrint

mov byte [2], al ;set freq
mov byte [3], 0x11
mov byte [2], al
mov byte [3], 0xa

%ifdef USE_SERIAL
mov ax, cx
call putint
mov al, 13
call putc
%endif

.skip_int:

iret

;es:di = buffer
;cx = count
serread:
push es
push ds

cld

mov ax, 0xc000
mov ds, ax

mov byte [8+4], 0b10 ;enable rts

.wait_loop:
test byte [8+5],1
jz .wait_loop ;no data

mov si, 8
movsb

mov ax, cx

cli
call putint
mov al,13
call putc

sti

loop .wait_loop




mov byte [8+4], 0

xor ax,ax
mov ds, ax


pop ds
pop es
ret

bios_disp_jump_table:
	dw putstring
	dw putint_dec
	dw putint
	dw putc
	dw putint_dec_s32
	dw clear_screen


;bx = func
bios_disp_handler:
	shl bx, 1
	add bx, bios_disp_jump_table
	call [cs:bx]
	
	iret

%include "vgmlib.asm"
	

vram_str: db "Testing VRAM...",10,0
cpu_str: db "Measuring processor speed...",10,0
init_complete: db 10,"Eagle-88 serial BIOS v0.2",10,"Ready for inputs",10,0
load_seg_msg: db "LOADING SEGMENT...",10,"Bytes remaining: ",10,0
segment_sz_str: db "SEGMENT SZ=",0

%DEFINE IN_ROM
%DEFINE USE_SERIAL
%include "iolib.asm"


music_file:
incbin "serial.vgm"




times 0x20000 - 0x10  - ($-$$) db 0

jmp 0xe000:0x0


times 0x20000 - 6 -($-$$) db 0
dw 0xcafe
dw bios_disp_handler ;for emulator
dw codeSeg
