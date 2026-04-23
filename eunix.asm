org 0x0

use16
cpu 8086 


stack equ 0x100
stackseg equ 0x50
fbSeg equ 0xa000


currX equ 0
currY equ 1

sys_params.mem_sz equ 2

lastKey equ 3
keyBuf equ 4

;end 8086 compatibility
_start:

cli


mov sp, stack
mov ax, stackseg
mov ss, ax

call iolib_setup

mov bx, 0xc000
mov es, bx
mov byte es:[0], 0
mov byte es:[1],SD_CS|SD_CLK|SD_TX
mov byte es:[6], 0
mov byte es:[7], 0xff




xor bx, bx
mov es, bx









mov bx, datSeg
mov ds, bx
mov es, bx

mov al, 0
xor di,di
mov cx, 0x1000
rep stosb


mov bx, 0
mov es, bx
xor dx, dx


mov byte [currX],3
call setcpos
mov al, 'K'
call putc
;memory check
.mem_sz_test:

xor bx, bx
.mem_sz_test_64k:
	
	mov ax, [es:bx]
	mov word [es:bx], 0xffff; check if write works
	cmp word [es:bx], 0xffff 
	jnz .end_of_mem
	dec word [es:bx] ;check if decrement works if value is already 0xff
	cmp word [es:bx], 0xfffe 
	jnz .end_of_mem
	mov [es:bx], al ;restor al
	
	test bx, 0x3ff
	jnz .skip_print_prog
	
	
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
	
	mov byte [currY],0

	mov si, ax
	mov al, ah
	add al, 0x30
	mov byte [currX], 2
	call setcpos
	call putc
	
	mov ax, si
	xor ah, ah
	
	div dl
	
	mov si, ax
	mov al, ah
	add al, 0x30
	mov byte [currX], 1

	call setcpos
	call putc
	
	mov ax, si
	xor ah, ah

	div dl
	
	mov si, ax
	mov al, ah
	add al, 0x30
	mov byte [currX], 0

	call setcpos
	call putc
	pop dx
	.skip_print_prog:
add bx,2
jnz .mem_sz_test_64k

add dx, 0x1000
mov es, dx
jnz .mem_sz_test

.end_of_mem:

mov byte [currY],0
mov byte [currX],0

;extrct memory size /256
mov al, bh
mov ah, dh ; seg top 
mov [sys_params.mem_sz], ax


call sd_cold_init


mov ax, 0xe000
mov ds, ax
mov si, init_complete
call putstring



xor ax, ax
mov ds,ax



xor ax, ax
mov es, ax
mov di, 0x9000
xor dx, dx
call sd_read_sector

mov ax, 0
mov ds, ax


mov si, 0x9000
call putstring


sti
;
.test:
cli 
jmp $

%include "iolib.asm"


setcpos:

ret

;ax = int
putint:
	push es
	push ax
	mov bx, 0xe000
	mov es, bx
	mov bx, ax
	push bx
	mov bl, bh
	shr bl, 1
	shr bl,1
	shr bl, 1
	shr bl,1
	xor bh,bh
	add bx, .lookup_table
	mov al, [es:bx]
	call putc
	pop bx
	push bx
	mov bl, bh
	and bl, 0xf
	xor bh,bh
	add bx, .lookup_table
	mov al, [es:bx]
	call putc
	pop bx
	
	push bx
	shr bl, 1
	shr bl,1
	shr bl, 1
	shr bl,1
	xor bh,bh
	add bx, .lookup_table
	mov al, [es:bx]
	call putc
	pop bx
	push bx
	and bl, 0xf
	xor bh,bh
	add bx, .lookup_table
	mov al, [es:bx]
	call putc
	pop bx
	pop ax
	pop es
	ret
.lookup_table: db "0123456789ABCDEF"


;si = string
putstring:
	cld
	
	.loop:
		lodsb
		test al, al
		jz .exit_loop
		push si
		call putc
		pop si
		jmp .loop
	.exit_loop:
	ret



vsyncstub:
iret


	
	
SD_TX EQU (1<<6)
SD_CLK EQU (1 << 5)
SD_CS EQU (1 << 4)
SD_RXCLK EQU (1<<3)

spi_flags equ 0 ;spi_flags bit 0 is cs

sd_write_dummy:
push ax
mov al,0xff
mov byte [spi_flags], 1
call sd_write
mov al, 0xff
call sd_write
mov byte [spi_flags],0
pop ax
ret


sd_cold_init:

xor dx, dx

mov bx, datSeg
mov es, bx
mov ds, bx


push es
mov bx, 0xc000
mov es, bx
mov byte [es:1], SD_CS

pop es

mov cx,12600
.spi_powerup_loop:
loop .spi_powerup_loop

mov byte [spi_flags], 1
mov cx, 12 ;send 12 ff dummy bytes for init
mov al,0xff
.init_loop:
call sd_write
loop .init_loop


mov byte [spi_flags], 0
mov cx, 12 ;send 12 ff dummy bytes for init
mov al,0xff
.init_loop2:
call sd_write
loop .init_loop2

mov byte [spi_flags], 1
mov cx, 12 ;send 12 ff dummy bytes for init
mov al,0xff
.init_loop3:
call sd_write
loop .init_loop3


mov byte [spi_flags],0

mov al, 0x40 ;send go_idle_state
call sd_write

xor al,al
call sd_write ;4 null params
call sd_write
call sd_write
call sd_write

mov al, 0x95 ;hard coded crc
call sd_write


call sd_read

cmp al, 1

jz .no_init_err
push ax
mov cx, 0xe000
mov ds, cx
mov si, .init_err
call putstring
pop ax
call putint

jmp $
.init_err db "SD INIT ERROR: RECEIVING SOMETHING OTHER THAN 1: ", 0
.init_success db "SD GO_IDLE_STATE SUCCESS",0xa,0
.init_cmd8_success db "SD CMD8 SUCCESS", 0xa, 0
.init_app_cmd db "SD APP SPEC CMD SUCCESS", 0xa,0
.acmd41_response db "SD ACMD41 RESPONSE: ",0

.no_init_err:

push ds
mov ax, 0xe000
mov ds, ax
mov si, .init_success
call putstring
pop ds


call sd_write_dummy

mov al, 0x48 ; CMD8 set voltage
call sd_write

xor al, al
call sd_write
call sd_write

mov al, 1
call sd_write
mov al, 0xaa
call sd_write ;check pattern
mov al ,0x87 ; CRC
call sd_write


call sd_read ; read cmd8 response
call sd_read_nopoll
call sd_read_nopoll
call sd_read_nopoll ; read voltage

call sd_read_nopoll ; read check pattern 



call sd_write_dummy


push ds
mov ax, 0xe000
mov ds, ax
mov si, .init_cmd8_success
call putstring
pop ds

call sd_write_dummy

mov al, 0x40 | 59 ;disable crc
call sd_write
xor al,al
call sd_write
call sd_write
call sd_write
mov al, 0
call sd_write 
mov al, 0x27
call sd_write

call sd_read

.resend_acmd41:
mov al, 0x40 | 55
call sd_write
xor al,al
call sd_write
call sd_write
call sd_write
call sd_write
mov al, 1
call sd_write

call sd_read

cmp al, 1
jz .no_err2

push ds
call putint
pop ds

.no_err2:

call sd_write_dummy


mov al, 0x40 | 41 ;acmd41
call sd_write
mov al, 0x40
call sd_write
xor al,al
call sd_write
call sd_write
call sd_write

mov al, 1
call sd_write

call sd_read

push ax
push ax
call sd_write_dummy
pop ax
push ds
push ax
mov si, 0xe000
mov ds, si
mov si, .acmd41_response
call putstring
pop ax
call putint
mov al, 10
call putc

pop ds

pop ax

test al,al
jnz .resend_acmd41



call sd_write_dummy

mov al, 0x40 | 58 ; read ocr

call sd_write
xor al,al
call sd_write
call sd_write
call sd_write
call sd_write
mov al,1
call sd_write

call sd_read
call sd_read_nopoll
call sd_read_nopoll
call sd_read_nopoll
call sd_read_nopoll

call sd_write_dummy

mov al, 0x40 | 16 ; set block size
call sd_write

xor al,al
call sd_write
call sd_write
mov al, 2
call sd_write ; 512
xor al,al
call sd_write

mov al, 1
call sd_write

call sd_read


ret

;al = cmdnum, ah = 
;returns al as response
sd_send_cmd_r1:
push ax
call sd_write_dummy
pop ax
or al, 0x40
call sd_write
xor al,al
call sd_write
call sd_write
call sd_write
mov al, 1
call sd_write 
mov al, 0xe5
call sd_write

call sd_read
ret


;es = seg
;di = destbuf
;dx:ax = sect
sd_read_sector:
	push cx
	push ds
	push es
	push di
	push dx
	push ax

	mov cx, 0xc000
	mov ds,cx

	
	mov cl, al
	
	call sd_write_dummy

	mov al, 0x40 | 17
	call sd_write
			
	mov al, dh ;addr[3]
	call sd_write

	mov al, dl ;addr[2]
	call sd_write

	mov al, ah ; addr[1]
	call sd_write
	
	mov al, cl
	call sd_write

	mov al, 1
	call sd_write 
	
		
	call sd_read ;r1
	cmp al, 0x0
	jz .no_err
	
	call putint
	jmp $
	

	.no_err:

	call sd_read_fe

;receive and store bytes
	cld
	mov cx, 512 ;blk sz
	.read_loop:
	call sd_read_nopoll
	stosb

	loop .read_loop

	call sd_read_nopoll; 16 bit crc ignore
	call sd_read_nopoll 

	pop ax
	pop dx
	pop di
	pop es
	pop ds
	pop cx
	ret

;al = read value
sd_read_fe:
        push cx
        push es
        push bx

        mov cx, 0xc000
        mov es, cx
        



	mov bl, SD_CLK|SD_TX
	
	.wait_for_zero_bit:
		and bl, ~SD_CLK
		mov [es:1], bl
	
		or bl, SD_RXCLK ;tick receiving shiftreg
		mov [es:1], bl
		and bl, ~SD_RXCLK
    
		mov [es:1], bl
		or bl, SD_TX ; send ffz
	
		or bl, SD_CLK
		mov [es:1], bl



        mov al, [es:1]
        cmp  al, 0xfe ;read from pcr address returns sdcard receiving shiftreg

        jnz .wait_for_zero_bit ;no zero.

        
        ;return value in al


        

        pop bx
        pop es
        pop cx
        ret


;al = read value
sd_read:
	push cx
	push es
	push bx

	mov cx, 0xc000
	mov es, cx
	
	mov bl, SD_CLK|SD_TX
	
	.wait_for_zero_bit:
	and bl, ~SD_CLK
	mov [es:1], bl
	
	or bl, SD_RXCLK ;tick receiving shiftreg
    mov [es:1], bl
    and bl, ~SD_RXCLK
    
    mov [es:1], bl
	or bl, SD_TX ; send ffz
	
	or bl, SD_CLK
	mov [es:1], bl

	


	mov al, [es:1]
	test  al, 1 ;read from pcr address returns sdcard receiving shiftreg
	
	jnz .wait_for_zero_bit ;no zero.

	mov cx, 7 
	or bl, SD_TX ; send ffz


	.receive_remaining:
	and bl, ~SD_CLK
	mov [es:1], bl
	
	or bl, SD_RXCLK ;tick receiving shiftreg
    mov [es:1], bl
    and bl, ~SD_RXCLK
    
    mov [es:1], bl

	or bl, SD_CLK
	mov [es:1], bl
	
	loop .receive_remaining
	
	;return value in al 
	mov al, [es:1]

	pop bx
	pop es
	pop cx
	ret 
sd_read_nopoll:
        push cx
        push es
        push bx

        mov cx, 0xc000
        mov es, cx

        
        mov cx, 8
		
        .receive_remaining:
	and bl, ~SD_CLK
	mov [es:1], bl
	
	or bl, SD_RXCLK ;tick receiving shiftreg
    mov [es:1], bl
    and bl, ~SD_RXCLK
    
    mov [es:1], bl
	or bl, SD_TX ; send ffz
	
	or bl, SD_CLK
	mov [es:1], bl

        loop .receive_remaining

        ;return value in al 
        mov al, [es:1]

        pop bx
        pop es
        pop cx
        ret


;al stores value to be sent, will be trashed
sd_write:
	push cx
	push es
	push bx
	
	mov cx, 0xc000
	mov es, cx ; MMIO segment
	
	mov cx, 8
	

	.send_loop:
	and bl, (~SD_TX)&(~SD_CS)

	;es : 1 = 0xc0001, PCR reg with sd controls
	test al, 0x80
	jz .zero
	
	or BYTE bl, SD_TX
		
	
	.zero:
	
	test BYTE [spi_flags], 0xff
	jz .cs_zero

	or BYTE bl, SD_CS
	.cs_zero:

	;tick sd clk

	and BYTE bl, ~SD_CLK ;mode 3
	mov BYTE [es:1], bl
	or bl, SD_RXCLK
	mov BYTE [es:1],bl
	and bl, ~SD_RXCLK
	mov BYTE [es:1],bl
	or BYTE bl, SD_CLK
	mov BYTE [es:1], bl

	rol al, 1
	
	loop .send_loop
	
	pop bx
	pop es
	pop cx
	ret
	





init_complete: db 10,"Eagle-88 serial bootloader v0.1",10,0

%include "libc.inc"

resb 0x20000 - 0x10- ($-$$) 

jmp 0xe000:0x0


resb 0x20000 - 2 -($-$$)

db 0xca, 0xfe
