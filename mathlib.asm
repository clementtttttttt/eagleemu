;clement's x86-16 math lib




	
	;[tmp_48_storage]:dx:ax = dividend & result (Q)
	;si:bp = divisor (M)
	;di:bx = remainder (A)

div_48_2:


	mov cx, 48
	
	
	xor di, di
	xor bx, bx
	
	xchg sp, [.tmp_48_storage]
	
	shl ax, 1
	rcl dx, 1
	rcl sp, 1
	rcl bx, 1
	rcl di, 1
	
	sub bx, bp
	sbb di, si
	
	
.div_loop:
	js .div_loop_is_neg

	stc
	rcl ax, 1
	rcl dx, 1
	rcl sp, 1
	rcl bx, 1
	rcl di, 1
	sub bx, bp
	sbb di, si
	
	loop  .div_loop
	
		xchg sp, [.tmp_48_storage]
	ret
	
.div_loop_is_neg:
	shl ax, 1
	rcl dx, 1
	rcl sp, 1
	rcl bx, 1
	rcl di, 1	
	add bx, bp
	adc di, si

	loop .div_loop
	
	
	xchg sp, [.tmp_48_storage]

	ret
.tmp_48_storage: dw 0
	

	;dx:ax = dividend & result (Q)
	;si:bp = divisor (M)
	;di:bx = remainder (A)

div_32:
	
	mov cx, 32 ;32 bit division + 1
	xor di, di
	xor bx, bx ;zero A
.div_loop:
	shl ax, 1
	rcl dx, 1
	rcl bx, 1
	rcl di, 1
	
	sub bx, bp
	sbb di, si
	
	js .div_neg ;negative
	inc al;set bottom bit of al
	loop .div_loop
	ret
.div_neg:
	;bottom bit of al is already empty
	add bx, bp
	adc di, si
	
	loop .div_loop
	ret

	;di:bx:si:bp = dividend & result
	;ax = remainder
div_64_by_1000:
	push bx
	
	
	test di, di
	jns .no_neg
	
	not di
	not bx
	not si
	not bp
	add bp, 1
	adc si,0  ; screw it it's probably still faster than doing it the loop way
	adc bx, 0
	adc di, 0 ;negate the stupid thing


	stc ; c flag = neg
	
	.no_neg:
	
	pushf
	
	mov cx, 1000 ;divisor = 1000

	mov ax, di
	xor dx, dx
	div cx
	mov di, ax
	
	mov ax, bx
	div cx
	mov bx, ax
	
	mov ax, si
	div cx
	mov si, ax
	
	mov ax, bp
	div cx
	mov bp, ax
	
	mov ax, dx ;move remainder from dx to ax
	
	popf

	pop bx
	
	
	jc .fix_negate
	
	
	ret
.fix_negate:
	
	not di
	not bx
	not si
	not bp
	add bp, 1
	adc si,0 
	adc bx, 0
	adc di, 0 ;negate the stupid thing
	
	
	ret

	;dx:ax = dividend & result
	;cx = divisor
	;bx = remainder
div_32_by_16:
	
	test dx, dx
	jns .no_neg
	

	neg dx
	neg ax
	sbb dx,0  ; screw it it's probably still faster than doing it the loop way
	
	stc ; c flag = neg
	
	.no_neg:
	
	pushf
	

	mov si, dx ;backup dx in si
	
	xchg ax, si 
	xor dx, dx
	div cx
	xchg ax, si
	
	div cx
	
	mov bx, dx ;move remainder from dx to bx
	mov dx, si ;restore dx
	
	
	popf
	
	
	jc .fix_negate
	
	
	ret
.fix_negate:
	

	neg dx
	neg ax
	sbb dx,0 
	
	
	ret


	;dx:ax = dividend & result
	;bx = remainder
div_32_by_1000:
	push cx
	
	test dx, dx
	jns .no_neg
	

	neg dx
	neg ax
	sbb dx,0  ; screw it it's probably still faster than doing it the loop way
	
	stc ; c flag = neg
	
	.no_neg:
	
	pushf
	
	mov cx, 1000 ;divisor = 1000

	mov si, dx ;backup dx in si
	
	xchg ax, si 
	xor dx, dx
	div cx
	xchg ax, si
	
	div cx
	
	mov bx, dx ;move remainder from dx to bx
	mov dx, si ;restore dx
	
	
	popf
	
	
	jc .fix_negate
	
	pop cx
	
	ret
.fix_negate:
	

	neg dx
	neg ax
	sbb dx,0 
	
	pop cx
	
	ret

direct_sqrt_port:
	mov al, bl
	test al, al
	;txa set flags
	jnz .lo
.do_lo:
	mov al, [.in_lo]
.lo:
	cmp al, 64
	jb .a0
.a1:
	cmp al, 12*12
	jb .a10
.a11:
	cmp al, 14*14
	jb .a110
.a111:
	cmp al, 15*15
	mov al, 7
	jnz .resume
.a110:
	cmp al, 13*13
	mov al, 6
	jnz .resume
.a10:
	cmp al, 10*10
	jb .a100
.a101:
	cmp al, 11*11
	mov al, 5
	jnz .resume
.a100:
	cmp al, 9*9
	mov al, 4
	jnz .resume
.a0:
	cmp al, 4*4
	jb .a00
.a01:
	cmp al, 6*6
	jb .a010
.a011:
	cmp al, 7*7
	mov al, 3
	jnz .resume
.a010:
	cmp al, 5*5
	mov al, 2
	jnz .resume
.a00:
	cmp al, 2*2
	jb .a000
.a001:
	cmp al, 3*3
	mov al, 1
	jnz .resume
.a000:
	cmp al, 1*1
	mov al, 0
.resume:
	rol al, 1
	cmp bl, 0
	jnz .cont
	ret
.cont:
	mov bh, al
	mov al, bl
	push bx
	xchg bl, bh
	xor bh,bh
	sub al, [bx+.sqtab-1]
	pop bx
	mov bl, al
	mov al, bh
	shl al, 1
	shl al, 1
	shl al, 1
	shl al, 1
	xor al, 0xff
	mov bh, al
	stc
	test bh, bh
	jns .loop3
.loop:
	shl al, 1
.loop2:
	adc al, [.in_lo]
	mov [.in_lo], al
	jc .plus
	dec bl
	js .done
	stc
.plus:
	dec bh
	mov al, bh
	js .loop
.loop3:
	rol al, 1
	dec bl
	jns .loop2
.done:
	mov al, bh
	xor al, 0xff
	ret
	
.sqtab:
	db  1,4,9,16,25,36,49,64,81,100,121,144,169,196,225
.in_lo: db 0
;dx;ax = niput & out
sqrt:
	
	

	ret
	
	
mul_32:
;dx:ax = multiplicand (M)
	;si:bp = multiplier (Q)
	
	;di:bx:si:bp = results (A)
	
	
	mov [.upper_multiplicand_storage], dx
	
	mov word [.result_storage], 0
	mov word [.result_storage+2], 0
	xor bx, bx
	xor di, di

		
	push ax
	
	mul bp ;first word of md and first word of multiplier
	
	mov [.result_storage], ax
	mov [.result_storage+2], dx
	
	pop ax
		
	mul si ;first word of md and second word of multiplier
	
	add [.result_storage+2], ax
	adc bx, dx
	
	mov ax, [.upper_multiplicand_storage]
		
	push ax
	
	mul bp ;second word of md and first word of multiplier
	
	add [.result_storage+2], ax
	adc bx, dx
	
	pop ax
		
	mul si ;first word of md and second word of multiplier
	
	add bx, ax
	adc di, dx
	
	mov bp, [.result_storage]
	mov si, [.result_storage+2]
	
	
	
	ret
.upper_multiplicand_storage: dw 0
.result_storage: dd 0



;dx:ax = input, x
log2_tab: dw 9002, 8005, 7011, 6022, 5044, 4087, 3169, 2321, 1584, 1000, 584, 321, 169, 87, 44, 22, 11, 5, 2
log2_n equ 9
log2_max equ 1000 ;1000+1000*pow(2,-N-1)
log2:
	xchg bx, bx
	;divide while it is larger than 1000 (algo range)
	xor si, si
	jmp .input_div_loop_start
	.input_div_loop:
		shr dx, 1
		rcr ax, 1
		add si, 1000
		
		.input_div_loop_start:
		
		test dx, dx
		jnz .input_div_loop
		
		cmp ax, 1000
		jae .input_div_loop
	
	push si
	
	;di:cx = newx
	;si:bp = z
	
	xor si, si
	xor bp, bp
	
	mov bx, -log2_n ;set range
		
	.loop:

		;newx = x + x*pow(2,-i)
		push ax
		push dx
		
		mov di, dx
		mov cx, ax
		
		
		test bx, bx 
		js .neg_shift
		xchg bx, cx
		shr ax, cl 
		xchg bx, cx
		;x/input should not be bigger than 1000
		jmp .end_shift
		.neg_shift:
		push bx
		neg bx
		.neg_shift_loop:
		shl ax, 1
		rcl dx, 1
		dec bx
		jnz .neg_shift_loop
				pop bx

		.end_shift:
		
		add cx, ax
		adc di, dx
		
		
		pop dx
		pop ax
		
		test di, di 
		jnz .skip_set ;certainly larger if upper word is set
		cmp cx, log2_max
		jnbe .skip_set
		
		mov dx, di
		mov ax, cx
		
		;z=z-tab[i+N]
		shl bx, 1
		sub bp, [log2_tab+log2_n*2+bx]
		sbb si, 0
		sar bx, 1
		
		
		.skip_set:
		
		
		inc bx
	cmp bx, log2_n
	jle .loop
		
	
	mov dx, si
	mov ax, bp
			pop si

	add ax, si
	adc dx, 0
	
	
	;add ax, si
	;adc dx, 0 
	
	xchg bx, bx
	ret
	
;base 2 exponential
;dx:ax = input(x)
;si:bp = z
exp2:
	mov cx, 2000 ;divide by 2000
	push dx
	call div_32_by_16	 ;result(dx:ax) = result shift count/2, modulo(bx) = x
	pop dx ;save sign
	
	shl al, 1	
		push ax

		


	mov bp, 1000 ;set z to 1000
	xor cx, cx
	cld
	
	test dx, dx
	js .x_is_neg
	;si not used till we multiply the result bhy off
	mov si, .exp2_tab
	
	.pos_loop:
		lodsw 
		test ax,ax
		jz .end
		cmp bx, ax
		jc .no_set_pos
		
		sub bx, ax
				
		mov ax, bp ;clone z
		shr ax, cl
		add bp, ax
		
		.no_set_pos:
		
		inc cx
		jmp .pos_loop
.x_is_neg:
	mov si, .exp2_neg_tab
	inc cx
	test bx, bx
	jz .end
	sub bx, 2000
	.neg_loop:
		lodsw	
		test ax, ax
		jz .end
		cmp bx, ax
		jg .no_set_neg
		
		sub bx, ax
		
		mov ax, bp
		shr ax, cl
		sub bp, ax
		
		.no_set_neg:
		inc cx
		jmp .neg_loop	
.end:	
	
	pop cx ;pop pushed count in cx
	
	
	xor dx, dx
	mov ax, bp
	
	xor ch, ch

	test cl,cl
	js .neg_off
	
	and cl, 0b11111
	jcxz .no_shift
	.pos_off_loop:
		shl ax, 1
		rcl dx, 1
		loop .pos_off_loop
	jmp .no_shift	
.neg_off:
	neg cl
	and cl, 0b11111	
	jcxz .no_shift
	.neg_off_loop:
		shr dx, 1
		rcr ax, 1
		loop .neg_off_loop
	

.no_shift:
	
	ret
.exp2_tab: dw 1000,585,322,170,87,44,22,11,6,3,1,1,0
.exp2_neg_tab: dw -1000, -415, -193, -93, -46, -23, -11, -6, -3, -1, -1, 0


cordic_sine_tab:
	dw 785, 463, 244, 124, 62, 31, 15, 7, 3, 1

;dx:ax = input (z)
;si:bp = x
;dx:ax = y
;fixed point

cordic_sin:
	;mod input
		
	mov di, 0x6228
	xor bp, bp ;0xc4500000 = 6282 << 18
	
	test dx, dx
	jns .no_neg_div
		neg di
		neg bp
	.no_neg_div:
	mov cx, 19
	jmp .mod_loop_start
	
.mod_loop:
	sar di, 1
	rcr bp, 1
	dec cx
	jz .mod_loop_end
.mod_loop_start:
	
	test di, di
	js .negcmp
	
	sub ax, bp
	sbb dx, di
	
	jge .mod_loop
	add ax, bp
	adc dx, di
	jmp .mod_loop
	
	.negcmp:
	
	
	sub ax, bp
	sbb dx, di
	
	jl .mod_loop
	add ax, bp
	adc dx, di
	jmp .mod_loop
.mod_loop_end:

	;correct negative remainder
	test ax, ax
	jns .no_abs
	
	add ax, 6282
	
.no_abs:


	mov bp, 607 ;0.607
	xor si, si
	xor bx, bx
	
		
	mov cx, ax
	
	;z>=1570?
	cmp cx, 1570
	jnge .no_sub_z
	
		mov ax, 3141
		sub ax, cx
		mov cx, ax
.no_sub_z:

	;z<=-1570?
	cmp cx, -1570
	jnle .no_plus
	
	add cx, 3141
	neg cx
	
.no_plus:
	
	
	xor ax, ax
	xor dx, dx
	
	;zero old x and y
	mov [.newx], bp
	mov [.newy], ax
	
	
.no_sub:
	
.loop:

	;calculate d*atantab[i]
	shl bx,1
	mov dx, [cordic_sine_tab+bx]
	shr bx, 1
	
	;calculate (d*y) >> i in di:cx
	;AND calculate (d*y) >> i in si:bp
	;AND calculate d*atantab[i]
	test cx, cx
	jns .skip_neg_y
		neg ax
		neg bp
		neg dx
	.skip_neg_y:
	
	xchg cx, bx

	sar ax, cl
	sar bp, cl
	
	xchg cx, bx
	
	sub [.newx], ax
	add [.newy], bp
	sub cx, dx
	
	mov bp, [.newx]
	mov ax, [.newy]
	
	inc bx
	cmp bx, 9
	jbe .loop
		
	cwd;sign extend 
	
	
	xor si, si
	xor di, di


	ret
	

.newx: dd 0
.newy: dd 0
	

; ax = input
;TODO: OPTIMISE
sin_16:
	shl ax, 1
	mov dx, ax
	or dx, 0x4000
	cmp ax, dx
	jnz .skip_fix
	
	mov dx, 0x8000
	sub dx, ax
	mov ax, dx
	
.skip_fix:

	and ax, 0x7fff
	shr ax, 1
	
	

cos_8:
	add al, 0x40
sin_8:
	mov bx, sinetab

	xlat
	ret
	
%macro inline_sin_8 0
	
	mov bx, sinetab

	xlat
%endmacro

%macro inline_sin_8_preset_bx 0

	xlat
%endmacro

%macro inline_cos_8 0
	add al, 0x40

	mov bx, sinetab


	xlat
%endmacro

%macro inline_cos_8_preset_bx 0
	add al, 0x40

	xlat
%endmacro

sinetab:
      db 0x00,0x03,0x06,0x09,0x0C,0x0F,0x12,0x15
      db 0x18,0x1C,0x1F,0x22,0x25,0x28,0x2B,0x2E
      db 0x30,0x33,0x36,0x39,0x3C,0x3F,0x41,0x44
      db 0x47,0x49,0x4C,0x4E,0x51,0x53,0x55,0x58
      db 0x5A,0x5C,0x5E,0x60,0x62,0x64,0x66,0x68
      db 0x6A,0x6C,0x6D,0x6F,0x70,0x72,0x73,0x75
      db 0x76,0x77,0x78,0x79,0x7A,0x7B,0x7C,0x7C
      db 0x7D,0x7E,0x7E,0x7F,0x7F,0x7F,0x7F,0x7F
      ;negative portion (for branchless)
      db 0x7f,0x7f,0x7f,0x7F,0x7f,0x7e,0x7e,0x7d
      db 0x7C,0x7c,0x7b,0x7a,0x79,0x78,0x77, 0x76
      db 0x75,0x73,0x72,0x70,0x6f,0x6d,0x6c,0x6a
      db 0x68,0x66,0x64,0x62,0x60,0x5e,0x5c,0x5a
      db 0x58,0x55,0x53,0x51,0x4e,0x4c,0x49,0x47
      db 0x44,0x41,0x3f,0x3c,0x39,0x36,0x33,0x30
      db 0x2e,0x2b,0x28,0x25,0x22,0x1f,0x1c,0x18
	  db 0x15,0x12,0x0f,0x0c,0x09,0x06,0x03,0x00
	;negative input
      db 0x00,0xfd,0xfa,0xf7,0xf4,0xf1,0xee,0xeb
      db 0xe8,0xe4,0xe1,0xde,0xdb,0xd8,0xd5,0xd2
      db 0xd0,0xcd,0xca,0xc7,0xc4,0xc1,0xbf,0xbc
      db 0xb9,0xb7,0xb4,0xb2,0xaf,0xad,0xab,0xa8
      db 0xa6,0xa4,0xa2,0xa0,0x9e,0x9c,0x9a,0x98
      db 0x96,0x94,0x93,0x91,0x90,0x8e,0x8d,0x8b
      db 0x8a,0x89,0x88,0x87,0x86,0x85,0x84,0x84
      db 0x83,0x82,0x82,0x81,0x81,0x81,0x81,0x81

      db 0x81,0x81,0x81,0x81,0x81,0x82,0x82,0x83
      db 0x84,0x84,0x85,0x86,0x87,0x88,0x89,0x8a
      db 0x8b,0x8d,0x8e,0x90,0x91,0x93,0x94,0x96
      db 0x98,0x9a,0x9c,0x9e,0xa0,0xa2,0xa4,0xa6
      db 0xa8,0xab,0xad,0xaf,0xb2,0xb4,0xb7,0xb9
      db 0xbc,0xbf,0xc1,0xc4,0xc7,0xca,0xcd,0xd0
      db 0xd2,0xd5,0xd8,0xdb,0xde,0xe1,0xe4,0xe8
	  db 0xeb,0xee,0xf1,0xf4,0xf7,0xfa,0xfd,0x00

	
	
