org 0x0
db "SG"
dw end_aqxe-_start
dw 0
dw codeSeg

use16
cpu 8086 


;end 8086 compatibility
_start:

cli

call iolib_setup


sti
; bx counts input buffer position
mov bx, 0

mov al, 27 + 0x80

monloop:
.notcr: cmp al, 8 + 0x80
jz .backspace
cmp al, 27 + 0x80
jz .esc
inc bl
jns .nextc
.esc: mov al, '\' + 0x80
call putc_wm
.getline: mov al, 10 + 0x80
call putc_wm
mov bl, 1
mov byte [currX], 1
.backspace: 
test byte [currX], 0xff
jz .fix_cx
dec byte [currX]
.fix_cx:
dec bl
js .getline
.nextc:

	.insert_own_keytest_routine_here_must_return_ax:
	sti

	call keytest
	or al, 0x80

	cli
	xor bh, bh
	mov [bx+ inBuf], al 
	call putc_wm
	cmp al, 10 + 0x80

	jnz .notcr
	
	mov bl, 0xff
	xor al, al
	xor cx, cx

.setstor:
 sal al, 1 
.setmode: mov [mode],al
.blskip: inc bl
.nextitem: 
xor bh, bh
mov al, [bx + inBuf]
cmp al, 10 + 0x80
jz .getline
cmp al, '.' + 0x80
jc .blskip
jz .setmode
cmp al, ':' + 0x80
jz .setstor

cmp al, 'r' + 0x80
jz .run
mov word [l], cx
mov [ysav], bl
xor bh,bh
.nexthex: 
mov al, [inBuf + bx]
xor al, 0xb0
cmp al, 0xa
jc .dig ;8088 has inverted carry
add al, 0xa9
cmp al, 0xfa
jc .nothex ;8088 has inverted carry
.dig:
mov cl, 4
sal al, cl
.hexshift:
sal al, 1
rcl word [l], 1
rcl word [segl],1
loop .hexshift

inc bl
jnz .nexthex
.nothex: cmp bl, [ysav]
jz .esc
test byte [mode], 0b01000000
jz .notstor
mov al, [l]
push es
les di, [stl]
stosb
pop es

inc WORD [stl]

.tonextitem: jmp .nextitem
.run: 
	jmp  far [xaml]
.notstor : 
	test byte al, [mode]
	js .xamnext
	mov cx, 4
	push bx
	xor bh,bh
.setadr: 
	mov bl, cl
	mov al, [(l-1)+bx]
	mov [(stl-1)+bx], al
	mov [(xaml-1)+bx], al
	loop .setadr
	pop bx
.nxtprnt: 
	jnz .prdata
	mov al, 10 + 0x80
	call putc_wm
	mov al, [xamlsegh]
	call .prbyte
	mov al, [xamlsegl]
	call .prbyte
	mov al, ',' + 0x80
	call putc_wm
	mov al, [xamh]
	call .prbyte
	mov al, [xaml]
	call .prbyte
	mov al, ':' + 0x80

call putc_wm

.prdata:
mov al, ' ' + 0x80
call putc_wm
push es
les si, [xaml]
es lodsb
pop es
call .prbyte

.xamnext:
	mov [mode], cl
	mov ax, [xaml]
	cmp ax, [l]
	
	jnc .tonextitem
	inc word [xaml]

	mov al, [xaml]
	and al, 0x7
	jmp .nxtprnt
.prbyte:
	push ax
	shr al, 1
	shr al, 1
	shr al, 1
	shr al, 1
	call .prhex
	pop ax
.prhex:
	and al, 0xf
	or al, '0' + 0x80
	cmp al, 0xba
	jnc .skip_p
	call putc_wm
	ret
	.skip_p:
	add al, 7
	call putc_wm
	ret

jmp monloop
.test:
cli 
hlt

putc_wm:
push ax
push bx
and al, 0x7f
call putc
pop bx
pop ax
ret

align 2
;al = ascii
inBuf times 256 db 0 ; CHAR[256]
mode db 0
l db 0
h db 0
segl db 0
segh db 0
ysav times 5 db 0
xaml db 0
xamh db 0
xamlsegl db 0
xamlsegh db 0
stl db 0
sth db 0
stsegl db 0
stsegh db 0

	
;%DEFINE USE_SERIAL
%include "iolib.asm"

end_aqxe:
db "RN"
dw _start
dw codeSeg
