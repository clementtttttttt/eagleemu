;si = source
;bx = offset 
;cx = count
memmove: 
	jcxz .skip_all ;no count
	
	push si
	push di
	
	test bx, bx
	js .off_neg
;move up
	std ;copy downwards
	
	add si, cx ;go to top of buffer 
	dec si ;minus one
	mov di, si ;clone si to di
	add di, bx ;add offset from si
	
	rep movsb ;copy the damn thing
	
	pop di
	pop si
	ret
.off_neg:
;move down
	cld  ;copy upwards
	
	mov di, si ;di and si both have the same value
	add di, bx ;add offset (negative) to di 
	
	rep movsb ;copy the stuff
	
	pop di
	pop si
.skip_all:
	ret
	

;moves variables to new basic_buf_end
varman_move_buf:
	push cx
	
	mov cx, [basic_buf_end]
	mov [basic_var_ptr], cx
	mov word [basic_var_sz], 0
	pop cx
	
	ret
	
;basic variable explanation: 
;buffer is a stream of tokens
;variable starts with an ID token and a data token follows
	
;si = pointer to id_token 
varman_decl_var:
	push di ;need to save di
	cld
	;copy over id token
	mov di, [basic_var_ptr] ;get base address
	add di, [basic_var_sz] ; go to end of it
	

	
	xor ch, ch ;empty top of count
	mov cl, [si+1] ;count at byte after id token
	add cx, 2 ;include 2 bytes (id token and string count)

	mov ax, si
	rep movsb ;copy id token to variable buffer
	mov si, ax ;backup and restore si
	

	mov al, TOK_EMPTY_VAR
	stosb ;no data in variable yet
	
	sub di, [basic_var_ptr]
	mov [basic_var_sz], di ; write new basic var size
	
	pop di
	ret

	
;VARMAN ARRAY FORMAT:
;(TOK_DIM:8)(VARTYPE:8)(NUMELEMENTS:16)
;si = pointer to id_token 
; dx = element count
;al = type
varman_decl_arr:
	push di ;need to save di
		cld;up

	;copy over id token
	mov di, [basic_var_ptr] ;get base address
	add di, [basic_var_sz] ; go to end of it
	
	xor ch, ch ;empty top of count
	mov cl, [si+1] ;count at byte after id token
	add cx, 2 ;include 2 bytes (id token and string count)
	
	rep movsb ;copy id token to variable buffer
	
	mov cl, al ;backup type in cl
	
	;type sanity check
	call varman_get_var_sz
	jnz .err_wrong_type
	
	
	mov al, TOK_DIM ;
	stosb ;store TOK_DIM token
	
	mov si, di ;store for getting self size later
	
	mov al, cl ; restore type to al
	stosb
	
	mov ax, dx ;array size is dx
	stosw
		
	call varman_get_arr_sz ;get self size (si stored earlier)
	add di, ax ;advance
	jc .err_overflow
	
	
	sub di, [basic_var_ptr]
	mov [basic_var_sz], di ; write new basic var size
	
	pop di
	ret
	
.err_wrong_type:
	mov si, .wrong_type_str
	xor bx, bx
	int 0xff
	return_after_error
.wrong_type_str:  db "Type not supported for array",0
.err_overflow:
	mov si, .overflow
	xor bx, bx
	int 0xff
	return_after_error
.overflow:  db "Array too large",0
	
;si = input
;ax = output
varman_get_arr_sz:
	
	lodsb ;get data type token and save it
	mov cl, al
		
	call varman_get_var_sz
	
	
	
	mov cl, ch
	xor ch, ch ; empty top part
	
	
	;type size includes initial token
	dec cx
	

	lodsw ; get count 
.fast_mul:
	shl ax, 1
	shr cx, 1
	jnc .fast_mul

	ret
	




varman_dump_vars:
	pusha_8088
	
	debug_print_message "VARMAN_DUMP_VARS"
	
	debug_print [basic_var_ptr]
	debug_print [basic_var_sz]
	
	cld
	mov si, [basic_var_ptr]
.loop:
	mov cx, [basic_var_ptr]
	add cx, [basic_var_sz]
	cmp si, cx;is there more
	jae .end ;no
	
	inc si
	lodsb ;count
	mov cl, al
	debug_print_8 cl
	xor ch, ch
	
	call putstring_cx ;put id
	
	mov al, 10
	push bx
	mov bx, 3
	int 0xff
	pop bx
	
	lodsb ;token
	debug_print_8 al;token type
	
	cmp al, TOK_DIM ;
	jz .arr_handling
	
	mov cl, al
	call varman_get_var_sz ;size
	mov cl, ch ;count low
	xor ch, ch
	dec cx
	add si, cx ;skip
	
	jmp .loop
.arr_handling:
	;si = pointer to arr, skips over data type and element count and stuff
	call varman_get_arr_sz
	add si, ax
	jmp .loop
.end:
	
	debug_print_message "END"
	debug_print_message ""
	popa_8088
	ret


;leaves variable address in di
;si = id token addressd
;cf = variable not found
varman_find_var:
	push dx
	push ax
	xchg si, di
	mov si, [basic_var_ptr]
	inc di ;incrmeent id token pointer to count
	mov bp, di ;save id token pointer in bp
	
	mov bx, si
	add bx, [basic_var_sz] ;get top of it
.find_loop:
	cld ;up

		
	cmp si, bx
	jae .error_end 
	
	inc si ;go to count in var buf

	lodsb
	scasb ;make sure we get the count of the current var we are looking at in the varbuf
	
	mov dx, si ;set ax to it for backup  
	
	jnz .not_match ;count does not match
	
	;count in al
	mov cl, al
	xor ch, ch
	
	repz cmpsb ;compare
	
	jnz .not_match 
	
	xchg si, di
	
	clc ;we have a match
	pop ax
	pop dx
	
	ret 
	
.not_match:
	mov di, bp ;restore si
	mov si, dx ;restore di
	
	xor ah, ah ;count in al
	add si, ax ; skip 
	
	;get var data size
	mov cl, [si] ;fetch token
	
	; is it an array
	cmp cl, TOK_DIM
	jz .arr_handling
	
	
	call varman_get_var_sz
	mov cl, ch ;data size in cl
	xor ch, ch
	add si, cx
	
	jmp .find_loop
.arr_handling:
	inc si
	call varman_get_arr_sz
	add si, ax
	jmp .find_loop


.error_end:
	
	
	lodsb ;load string length count to al
	xor ah, ah
	add si, ax ;go to end
	
	xchg si, di
	stc
	
	pop ax
	pop dx
	ret
	
	
varman_err:
	mov si, .varman_err_str
	xor bx, bx
	int 0xff
	return_after_error
	
.varman_err_str: db "Nonexistent variable",0

; cl = token type
; di = pointer to token
; ch = size
;zf = equal
;cf = will be power of two
varman_get_var_sz:
	cmp cl, TOK_FP
	jz .fp
	cmp cl, TOK_NUM
	jz .num
	cmp cl, TOK_EMPTY_VAR
	jz .empty
	mov ch, 0
	
	ret
.fp:
	mov ch, 5
	stc
	ret
.num:
	mov ch, 3
	stc
	ret
.empty:
	mov ch, 1
	ret

;si = pointer to id token	
;dx:ax = data
;cl = token type
varman_set_var:
	push di
	push bx
	
	push cx 
	call varman_find_var
	pop cx
	jc varman_err

	cmp byte [di], TOK_DIM ;arrays have constant size
	jz .set_arr

	;di now at variable data address
	;calculate variable data size
	call varman_get_var_sz
	
	push cx
	
	mov bl, ch ;backup new variable size
	mov cl, [di]
	call varman_get_var_sz
	xor bh, bh
	sub bl, ch ;get difference
	;no difference no moving
	jz .skip_memmove
	
	mov si, di;start of buffer
	mov cx, [basic_var_sz]
	add cx, [basic_var_ptr];get end of buffer
	sub cx, di ;get count
	;difference already in bx
	
	
	call memmove
	
	add [basic_var_sz], bx ;add offset to size

.skip_memmove:

	pop cx
	
	mov [di], cl  ;set token
	inc di
	cmp cl, TOK_FP
	jz .set_fp
	cmp cl, TOK_NUM
	jz .set_int
	

	jmp $
	

.set_arr:
	cld
	push dx
	push ax ;preserve data to be set
	lodsb 
	cmp al, TOK_IDX
	jnz bad_idx_error
	

	
	push di
	mov di, si
	call parse_exp
	cmp byte [di-1], TOK_IDXEND
	jnz bad_idx_error
	
	;check if dx:ax is larger than 1000
	cmp dx, 0x3e7
	jae .check_of
	
	.no_of:
		pop di

	mov bx, 1000
	;divide dx:ax by 1000
	div bx
	

	;di points to array token

	inc di
	
	;array type checking 
	cmp cl, [di]
	jnz bad_type_err
	
	inc di
	
	
	;check if index is larger than array
	scasw
	jae oob
	

	;get array type  size
	call varman_get_var_sz
	
	
	mov bl, ch ;array size into bl
	xor bh,bh
	
	dec bx ;decrement size by 1
	
	shr bx, 1 ;dec count by 1
	
.fast_mul:
	shl ax, 1 ; multiply index with size
	shr bx, 1
	jnc .fast_mul
	
	add di, ax ;go to data
	
	
	pop ax
	pop dx
	
	
	cmp cl, TOK_NUM
	jz .set_int
	
.set_fp:
	mov [di], dx
	add di, 2
.set_int:

	mov [di], ax
	
.done_set:
	
	pop bx
	pop di
	
	;we should be done here
	
	ret
.check_of:
	cmp ax, 0xfc18
	jb .no_of
	
	jmp oob
	
;si = pointer to id token  and index if needed
;
;return values:
;cl = token type
;dx:ax = token data

varman_get_var:
	push di
	push bx
	
	call varman_find_var
	jc varman_err
	
	mov cl, [di] ;di alrady points to data token
	inc di ;skip over token
	cmp cl, TOK_FP
	jz .fp
	cmp cl, TOK_NUM
	jz .num
	cmp cl, TOK_DIM
	jz .arr
	
	;FIXME: will have to deal with this some time later
	jmp $
	
.arr:
	inc di
	
	push di
	mov di, si
	
	mov al, TOK_IDX
	scasb ;compare al with byte at si
	jnz bad_idx_error ;is the index exp terminated
	
	call parse_exp.recurse
	
	cmp byte [di-1], TOK_IDXEND
	jnz bad_idx_error ;is the index exp terminated
	
	mov si, di
	
	;predivide value by 8
	
	
	pop di
	
	;check if index is greater than 0xffff
	cmp dx, 0x3e7
	jae .check_of
	
.no_of:
	mov bx, 1000 ;divide by 1000
	div bx ;divided in ax
	
	mov bx, [di]; get element count
	
	cmp ax, bx
	jae oob ;index out of bounds
	
	add di, 2 ;goto data
	
	;get array data type size
	mov cl, [di-3]
	call varman_get_var_sz
	
	;index in ax
	;var size in ch
	;var type in cl moved to bl
	mov bl, cl
	
	mov cl, ch
	xor ch, ch
	
	dec cl 
	shr cx, 1
	
.fast_mul_loop:
	shl ax, 1
	shr cx, 1
	jnc .fast_mul_loop
	

	add di, ax
	
	mov cl, bl
	;done
	cmp cl, TOK_NUM
	jz .num 
	
.fp:
	
	mov dx, [di] ;upper bits
	add di, 2
.num: 
	mov ax, [di] ;lower bits	

	
	pop bx
	pop di
	ret

.check_of:
	ja oob
	
	cmp ax, 0xfc18
	jb .no_of
	;falls through
oob:
	mov si, oob_str
	xor bx, bx
	int 0xff
	return_after_error

bad_type_err:
	mov si, .bad_type_str
	xor bx, bx
	int 0xff
	return_after_error
.bad_type_str: db "Array type differs from value type",0

bad_idx_error:
	mov si, .bad_idx_str

	xor bx, bx
	int 0xff
		return_after_error
.bad_idx_str: db "Index syntax error",0

oob_str: db "Index out of bounds",0
