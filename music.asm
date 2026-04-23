org 0
cpu 8086
;cpu 186

db "SG"
dw end_f-start_f
dw 0
dw codeSeg

start_f:

start:
	mov ax, 0xc000
	mov es, ax
	mov ax, 0x900
	mov ds, ax

	mov di, 0x13
	mov bx, 0x12

	mov byte [es:di], 7
	mov byte [es:bx], 0xff

	mov byte [es:di], 0xf

	mov byte [0], 0
	mov word [count], startCount
	inc word [count]
	.loop:
		mov al, [0]
		not al
		mov [es:bx], al
		mov [0], al

		mov cx, [count]
		shr cx, 1	
	
		jcxz .no_loop2
		.loop2:
		;	not dl
			mov [es:bx], al
			loop .loop2
		.no_loop2:

		mov al, [0]
		not al
		mov [es:bx], al
		mov [0], al

		mov cx, [count]
		shr cx, 1
		
		jcxz .no_loop3
		.loop3:
		;	not dl
			mov [es:bx], al
			loop .loop3
		.no_loop3:
		
		inc word [count]

		cmp word [count], 0x200
		jbe .loop
		
		mov word [count], startCount
		jmp .loop

count: db 0
end_f:


db "RN"
dw start
dw codeSeg

startCount equ 0x60
codeSeg equ 0x100
