libc_begin:

.libc_func_tab:
dw .memccpy
dw .memchr
dw .memcpy
dw .memmove
dw .memset
dw .memcmp

dw .strcpy
dw .strncpy
dw .strcat
dw .strncat
dw .strchr
dw .strrchr
dw .strpbrk
dw .strtok_r

dw .strcmp
dw .strncmp
dw .strlen
dw .strspn
dw .strcspn
;GCC-ia16 abi: clobber a,b,c,d others must be preserved ss = ds

.string_begin:
	.strtok_r: ;TODO: testhis 
		mov bx, sp
		push si
		push di
		push bp

		mov si, [bx+2] ;s	

		mov di, [bx+4] ;sep


		mov di, [bx+6] ;save
		mov bp, [di]
	
		
		test si, si
		jnz .skip_strtok_quit_cond

		cmp si, bp
		jz .skip_strtok_quit_cond
		xor ax, ax
		jmp .strtok_ret_null

		.skip_strtok_quit_cond:

		push di
		push si

		call .strspn

		add sp, 4 ;pop 2

		add si, ax
		test byte [si], 0xff
		jnz .skip_ret_and_set_p
	.strtok_ret_and_set_p:
		mov word [di], 0 ;set p to 0
		jmp .strtok_ret_null

		.skip_ret_and_set_p:

		push di
		push si

		call .strcspn

		add sp, 4;pop 2
		
		mov [di], si
		add [di], ax

		mov dl, [bp]
		test byte dl, 0xff ;if(**p) 

		jz .strtok_ret_and_set_p

		inc byte [di]

		mov byte [di] ,0

		mov ax, si

		.strtok_ret_null:

		pop bp
		pop di
		pop si

		

		ret 	
	.strpbrk:
		
		mov bx, sp
		push si
		mov si, [bx+2]
		
	
		push word [bx+4]
		push si
		call .strcspn
		add sp, 4 ;pop


		add si, ax;add offset returned byh strcspn

		xor ax, ax
		test BYTE [si], 0xff 
		
		jz .skip_ret

		mov ax, si

		.skip_ret:

		pop si
	ret
        .strcspn:
                mov bx, sp
                push si
                push bp

                mov bp, [bx+2] ; dest
                mov dx, [bx+4] ; list

                cld
                xor ah, ah
                .strcspn.l:
                        mov al, [bp]
                        
                        mov si, dx
			xor ah, ah

                        .strcspn.cmp.l:
                                lodsb

                      
                                cmp al, [bp]
                                jnz .strcspn.l.skip_set ;found different letter
                                mov ah, 1
                                .strcspn.l.skip_set:
                                
				test al,al
				jz .strcspn.cmp.l.end

				inc si
                                jmp .strcspn.cmp.l
                        .strcspn.cmp.l.end:
                        test ah, ah
                        jnz .strcspn.l.not_found ;we found one somewhere

                        pop si
                        inc bp
                        jmp .strcspn.l



                .strcspn.l.not_found:
                mov ax, bp
                sub ax, [bx+2] ;subtract by original

                .strcspn.cmp.end:

                pop bp
                pop si
                ret


        .strspn:
		mov bx, sp
		push si
		push bp

		mov bp, [bx+2] ; dest
		mov dx, [bx+4] ; list

		cld 
		xor ah, ah
		.strspn.l:
			mov al, [bp]
			test al, al ;nul
			jz .strspn.l.not_found

			mov si, dx
                             
			.strspn.cmp.l:
				lodsb
				
				test al, al
				jz .strspn.cmp.l.end ;reached end of list of chars 
                                cmp al, [bp]
                                jz .strspn.l.skip_set ;found different letter		
				mov ah, 1
				.strspn.l.skip_set:
				inc si
				jmp .strspn.cmp.l
			.strspn.cmp.l.end:
			test ah, ah
			jnz .strspn.l.not_found ;we found one somewhere

			pop si
			inc bp
			jmp .strspn.l

	

		.strspn.l.not_found:
		mov ax, bp
		sub ax, [bx+2] ;subtract by original
				
		.strspn.cmp.end:

		pop bp
		pop si
		ret
		
	.strrchr:
                push si
                push bx

                mov bx, sp
                mov si, [bx + 6] ;dest
                mov ax, [bx + 8] ; c
            
		push si		;strlen call

		call .strlen

		add sp, 2 ;pop
		
		inc ax ;include zero
		add si, ax
		

		mov cx, ax ;count is len returned by strlen in ax

	    	std ;down
                xor ah, ah
                .strrchr_loop:
                lodsb


                cmp al, dl
                jz .strrchr_found

                test al, al
                jz .strrchr_not_found

                loop .strrchr_loop

                xor ax, ax
                jmp .strrchr_not_found

                .strrchr_found:

                mov ax, si

                .strrchr_not_found:

                pop bx
                pop si
                ret


        .strchr:
                push si
                push bx

                mov bx, sp
                mov si, [bx + 6] ;dest
                mov ax, [bx + 8] ; c
                cld
		xor ah, ah                
		.strchr_loop:
		lodsb


		cmp al, dl
		jz .strchr_found

		test al, al
		jz .strchr_not_found

		loop .strchr_loop
		
		xor ax, ax
		jmp .strchr_not_found

		.strchr_found:

                mov ax, si

		.strchr_not_found:

                pop bx
                pop si
                ret


        .strncat:
                mov bx, sp

                ;this func adds the string length to the dst operand and  strcpys the old to new
                push WORD [bx+2] ;first arg
                ;get address first by getting strlen

                call .strlen
                add sp, 2 ; pop

		push di
		push si

		mov di, [bx+2]
		inc ax
                add [bx+2], ax ;add offset to dest arg
		
		mov si, [bx+4]
			

		mov cx, [bx+6] ; count
		cld
		
		.strncat_loop:

		lodsb
		test al, al
		jz .strncat_loop_end
		stosb

		loop .strncat_loop

		inc di
		.strncat_loop_end:
		
		mov word [es:di], 0

		pop si
		pop di
			

                ret

	.strcat:
		mov bx, sp
		
		;this func adds the string length to the dst operand and  strcpys the old to new		
		push WORD [bx+2] ;first arg 	
		;get address first by getting strlen
		
		call .strlen
		add sp, 2 ; pop
	
		inc ax	
		add [bx+2], ax ;add offset to dest arg 
		
		push word [bx+4]
		push word [bx+2]

		;ATTENTION: stack frame should be pre-setup for strcpy buti'm not sure, praying that it works  
		call .strcpy
	
		add sp, 4 ;pop 2

		ret
	.strlen:
		push si
		push bx

		mov bx, sp
		mov si, [bx + 6] ;string

		cld 
		.strlen_loop:
			lodsb 
			test al, al
			jnz .strlen_loop

		mov ax, si
		sub ax, [bx+6] ; original val
		dec ax ;dec by one 

		pop bx
		pop si

		ret 

	 .strncmp:
                push di
                push si
                push bx

                mov bx, sp
                mov di, [bx+8] ;op 1
                mov ax, di ;op 2
                mov si, [bx+10] ; src
                mov cx, [bx+12] ; count

                cld

                .strncmp.l:
                        lodsb
                        cmp al, [di]
                        jnz .strncmp.end_l ; not equ
                        test al, al
                        jz .strncmp.end_l ;end of string
                        inc di
                        loop .strncmp.l
                .strncmp.end_l:

                mov ax, [di]
                sub ax, [si]

                pop bx
                pop si
                pop di

                ret

	 .strcmp:
                push di
                push si
                push bx

                mov bx, sp
                mov di, [bx+8] ;op 1
                mov ax, di ;op 2
                mov si, [bx+10] ; src
                cld
                
		.strcmp.l:
			lodsb
			cmp al, [di]
			jnz .end_l ; not equ
			test al, al
			jz .end_l ;end of string
			inc di
			jmp .strcmp.l
		.end_l:

                mov ax, [di]
                sub ax, [si]

                pop bx
                pop si
                pop di

	 	ret
         .strcpy:
                push di
                push si
                push bx

                mov bx, sp
                mov di, [bx+8] ;dest
                mov ax, di ;return dest
                mov si, [bx+10] ; src
                cld
                .strcpy.l:
			lodsb
			stosb
			test al, al
			jnz .strcpy.l

                pop bx
                pop si
                pop di
                ret
         .strncpy:
                push di
                push si
                push bx

                mov bx, sp
                mov di, [bx+8] ;dest
                mov ax, di ;return dest
                mov si, [bx+10] ; src
                mov cx, [bx+12] ;count
		cld
                .strncpy.l:
                        lodsb
			.zero: ;jumps here when al is 0 aka fill buffer, i'm a bloody genius
                        stosb
                        test al, al
                        jnz .strncpy.l
			loop  .zero
                pop bx
                pop si
                pop di
                ret

	.memccpy:
                push di
                push si
                push bx

                mov bx, sp
                mov di, [bx+8] ;dest
                mov ax, di ;return dest
                mov si, [bx+10] ; src
		mov dx, [bx+12] ;char
		mov cx, [bx+14] ;count

                cld
                .memccpy.l:
                        lodsb
                        stosb
                        
			
			cmp al, dl
                        jz .found
	
                	loop .memccpy.l
		xor ax, ax
		jmp .not_found

		.found:

		inc di
		mov ax, di ;byte after detect
		.not_found:

	
		pop bx
                pop si
                pop di
                ret


	 .memcmp:
                push di
                push si
                push bx

                mov bx, sp
                mov di, [bx+8] ;op 1
                mov ax, di ;op 2
                mov si, [bx+10] ; src
                mov cx, [bx+12] ; count
                cld
                repe cmpsb

		mov ax, [di]
		sub ax, [si]

                pop bx
                pop si
                pop di
                ret

	.memchr:
                push di
                push bx

                mov bx, sp
                mov di, [bx + 6] ;dest
                mov al, [bx + 8] ; c
                mov cx, [bx + 10] ; count
                cld
                rep scasb

		xor ax, ax

		test cx, cx
		jz .ret_nullptr
                mov ax, di
		.ret_nullptr:

                pop bx
                pop di
                ret

	
	.memcpy:
		push di
		push si
		push bx

		mov bx, sp
		mov di, [bx+8] ;dest	
		mov ax, di ;return dest
		mov si, [bx+10] ; src
		mov cx, [bx+12] ; count
		cld 
		rep movsb

		pop bx
		pop si
		pop di
		ret
	.memset:
		push di
		push bx

		mov bx, sp
		mov di, [bx + 6] ;dest
		mov dx, di ; return dset
		mov al, [bx + 8] ; c
		mov cx, [bx + 10] ; count
		cld 
		rep stosb

		mov ax, dx

		pop bx
		pop di
		ret
	.memmove:
		push di
		push si
		push bx

		mov bx, sp
		mov di, [bx + 8]
		mov ax, di
		mov si, [bx+10]
		mov cx, [bx+12]

		cmp di, si ; di < si
		jz .end
		jae .invert

		cld

		jmp .end_cond
		.invert:
		
		std
		add si, cx
		dec si
		add di, cx
		dec di

		.end_cond:


		rep movsb

		.end:
		

		pop bx
		pop si
		pop di
		ret


.string_end:






















libc_end:
