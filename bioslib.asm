


%IFDEF IN_ROM
codeSeg equ 0xe000
datSeg equ 0x60
currX equ 0
currY equ 1
stackseg equ 0x3000
stack equ 0xffff
shift equ 5
vsynclock equ 2
lastKey equ 3
keyBuf equ 4

%ELSE
codeSeg equ 0x100
stackseg equ 0x3000
stack equ 0xffff
datSeg equ codeSeg
currX db 0
currY db 0
shift db 0
vsynclock db 0
lastKey db 0
keyBuf db 0


%ENDIF

SD_CLK EQU (1 << 5)
SD_CS EQU (1 << 4)
SD_RXCLK EQU (1<<3)
SD_TX EQU (1<<6)

fbSeg equ 0xa000


serint:
;%IFDEF USE_SERIAL
push ax
push ds 
mov ax, 0xc000
mov ds, ax

push si
mov si, 8
lodsb
pop si
mov [0], al
pop ds

%ifdef USE_KEY_CALLBACK

call key_callback ;can only clobber ds and ax
%endif


mov [keyBuf], al


cmp al, 7 ;is it bell char
jnz .no_reset ; do not reset if not
jmp 0xffff:0
.no_reset:

pop ax
;%ENDIF
iret


%ifndef USE_OWN_VSYNC
vsync:
	
	iret

%endif

iolib_setup:
	
	mov bp, sp
	mov bx, [bp] ;get return value

	mov ax, stackseg
	mov ss, ax
	mov sp, stack
	

	push bx ;push it
	
	mov bx, 0xc000
	mov es, bx
	mov byte es:[0], 0
mov byte es:[1],SD_CS|SD_CLK|SD_TX
	mov byte es:[6], 0
	mov byte es:[7],0xff
	.uart_init:
	mov byte es:[8+3], 0x80;dlab
	mov byte es:[8+4], 2 ; enable all 
	mov byte es:[8], 1;115200
	mov byte es:[9], 0;115200
	mov byte es:[8+3], 0b0000111 ;8 bit, two stop bits
	mov byte es:[8+1], 1b; yes ints
	;mute all channels
	mov byte es:[3], 0x1c
	mov byte es:[2], 0x0


	xor bx,bx
	mov es,bx
	mov word [es:0], vsync
	mov word [es:2], codeSeg
	mov word [es:4*1], serint
	mov word [es:4*1+2], codeSeg
	mov word [es:4*3],keyint
	mov word [es:4*3+2],codeSeg
		mov bx, 0xa000
	mov es, bx
	xor al, al
	xor di, di
	mov cx, 320/8*500
	rep stosb

	mov bx, datSeg
	mov es, bx
	mov ds, bx
	mov byte es:[currY],0
	mov byte es:[currX],0
	mov word es:[shift], 0
	
	
	
	mov bx, 5
	int 0xff
	


	ret
	

keyint:
push bx

push cx 
push ax

push ds

mov cx, 0xc000
mov ds, cx
mov al, [0005] 
mov [0], al
pop ds

cmp al, 0x5
jnz .skip_hard_reset

jmp 0xffff:00

.skip_hard_reset:

cmp al, 0xf0
jz .skip_setkeybuf


cmp BYTE [lastKey], 0xf0
jz .skip_setkeybuf


cmp al, 0x12

jnz .skip_setshift
push ds
mov bx, datSeg
mov ds, bx
mov word [shift], ps2lookupupper-ps2lookup
pop ds
jmp .setshift_skip
.skip_setshift:

push ds
mov cx, datSeg
mov ds, cx
mov bx, [shift]
mov cx, codeSeg
mov ds,cx
add bx, ps2lookup
xlatb
pop ds


push ds
mov bx, datSeg
mov ds, bx



%ifdef USE_KEY_CALLBACK

call key_callback
%endif

mov [keyBuf], al



pop ds
.skip_setkeybuf:

push ds
mov bx, datSeg
mov ds, bx
mov [lastKey], al

cmp al, 0x12

jnz .skip_unsetshift
mov byte [shift], 0
.skip_unsetshift:

pop ds

.setshift_skip:

pop ax
pop cx
pop bx

iret

ps2lookup:
	db 0, 0, 0, 0, 0, 0, 0, 0
	db 0, 0, 0, 0, 0, 9, '`', 0
	db 0, 0 , 0 , 0, 0 , 'q', '1', 0
	db 0, 0, 'z', 's', 'a', 'w', '2', 0
	db 0, 'c', 'x', 'd', 'e', '4', '3', 0
	db 0, ' ', 'v', 'f', 't', 'r', '5', 0
	db 0, 'n', 'b', 'h', 'g', 'y', '6', 0
	db 0, 0, 'm', 'j', 'u', '7', '8', 0
	db 0, ',', 'k', 'i', 'o', '0', '9', 0
	db 0, '.', '/', 'l', ';', 'p', '-', 0
	db 0, 0, 0x27, 0, '[', '=', 0, 0
	db 0, 0, 10, ']', 0, 92, 0, 0
	db 0, 0, 0, 0, 0, 0, 8, 0
	db 0, '1', 0, '4', '7', 0, 0, 0
	db '0', '.', '2', '5', '6', '8', 27, 0 
	db 0, '=', '3', '-', '8', '9', 0, 0
	db 0, 0, 0, 0
ps2lookupupper:
        db 0, 0, 0, 0, 0, 0, 0, 0
        db 0, 0, 0, 0, 0, 9, '`', 0
        db 0, 0 , 0 , 0, 0 , 'Q', '!', 0
        db 0, 0, 'Z', 'S', 'A', 'W', '2', 0
        db 0, 'C', 'X', 'D', 'E', '4', '#', 0
        DB 0, ' ', 'V', 'F', 'T', 'R', '5', 0
        DB 0, 'N', 'B', 'H', 'G', 'Y', '6', 0
        DB 0, 0, 'M', 'J', 'U', '&', '*', 0
        DB 0, '<', 'K', 'I', 'O', ')', '(', 0
        DB 0, '>', '?', 'L', ':', 'P', '_', 0
        DB 0, 0, '"', 0, '[', '+', 0, 0
        DB 0, 0, 10, ']', 0, 92, 0, 0
        DB 0, 0, 0, 0, 0, 0, 8, 0
		db 0, '1', 0, '4', '7', 0, 0, 0
		db '0', '.', '2', '5', '6', '8', 27, 0 
		db 0, '+', '3', '-', '8', '9', 0, 0
		db 0, 0, 0, 0


keytest:
	push ds
	mov ax, datSeg
	mov ds, ax
	sti
	.waitkey:
	mov al, [keyBuf]
	test al, al
	jz .waitkey
	cli
	
	mov byte [keyBuf], 0

	pop ds
	ret


