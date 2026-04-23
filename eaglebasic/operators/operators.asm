

%macro pop_op_stack_16 1
	mov word %1, [bx]
	add bx, 2
%endmacro

%macro pop_op_stack_8 1
	mov byte %1, [bx]
	inc bx
%endmacro

%macro push_op_stack_16 1
	sub bx, 2
	mov word [bx], %1

%endmacro

%macro push_op_stack_8 1
	dec bx
	mov byte [bx], %1
%endmacro

%macro push_num_to_op_stack 1
	push_op_stack_16 %1
	push_op_stack_8 TOK_NUM
%endmacro

%macro pop_fp_from_op_stack 0
	pop_op_stack_16 ax
	
	pop_op_stack_16 dx
%endmacro

%macro push_fp_to_op_stack 0
	push_op_stack_16 dx
	
	push_op_stack_16 ax
	
	push_op_stack_8 TOK_FP
%endmacro

%macro op_assert_nonempty_stack 0
	cmp bx, op_stack
	jz op_error_handling
%endmacro


%macro op_get_two_args 0
	xor di, di
	call op_get_arg
	mov cx, ax ;backup second arg to cx
	mov si, dx ; incase it is fixed
	rcl di, 1
	
	call op_get_arg
	rcl di, 1
%endmacro
	
	
	

	




op_cast_args_to_fp:

	;fixed point addition
	test di, 1
	jz  .cast_2
	
	test di, 0b10
	jz .cast_1
.no_cast:

	ret

.cast_2:
	
	;cast dx:ax to an fp value (mul 1000)
	xchg dx, ax 
	
	mov dx, 1000
	mul dx
	
	test di, 0b10
	jnz .no_cast
.cast_1:
	
	mov cx, si
	
	xchg dx, si
	xchg ax, cx
	
	mov dx, 1000
	mul dx
	
	xchg dx, si
	xchg ax, cx

	ret
	
;gets a numerical arugment from stack, CF=is fixed, dx:ax=fixed, dx=int,  when int, handles error
op_get_arg:
	
	pop_op_stack_8 al 
	cmp al, TOK_FP 
	jz .fixed_handling
	cmp al, TOK_ID
	jz .var_handling
	cmp al, TOK_PTR
	jz .ptr_handling
	cmp al, TOK_NUM
	jnz op_error_handling
	
	
	
	;integer token handling goes here
	pop_op_stack_16 dx
	clc
	
	ret
.ptr_handling:
	pop_op_stack_16 si
	mov ax, es
	pop_op_stack_16 es
	
	mov dx, [es:si]
	mov es, ax
	xor dh, dh
	clc
	ret
	
	
.var_handling:
	
	push cx
	push si

	pop_op_stack_16 si
	
	call varman_get_var
	
	pop si
	
	
	cmp cl, TOK_FP
	jz .fp_var
	cmp cl, TOK_NUM 
	jz .num_var
	jmp $
.fp_var:
		pop cx

	stc
	ret
	
.num_var:
	mov dx, ax 
	clc
		pop cx

	ret
	
.fixed_handling:

	pop_fp_from_op_stack
	stc

	ret
	

op_error_handling:
	xor sp, sp
	mov si, .parse_err_msg
	xor bx, bx
	int 0xff
	jmp beforegetline ;abort
.parse_err_msg: db "Operator error",0



;al = token
%macro op_run_func 0
	inc di
	
	xor bh, bh
	
	mov bl, al
	js .op_run_func_err ;shouldn't be negative
	shl bx, 1 ;multiply by two since each entry in table is 16 bits
	mov ax, [op_tab+bx-6] ;;grab it and save in ax
	
	cmp ax, 0xdead
	jz .op_run_func_err
	
	mov bx, [op_stack_ptr]

	push di
	call  ax ;call it
.op_run_func_exit:	
	pop di

	;funciton expected to leave stack pointer in bx
	mov [op_stack_ptr], bx
	
.end:
	jmp parse_exp.exp_loop
.op_run_func_err:
	mov si, .op_run_func_err_str
	push bx
	xor bx,bx
	int 0xff
	pop bx
	mov ax, bx ;token in bx
	mov bx, 2 ;print token number
	int 0xff
	 	xor sp, sp
	jmp beforegetline

.op_run_func_err_str: db "No func for op token 0x",0
	%endmacro

op_less:
	op_get_two_args
	test di, 0b11
	jnz .fp
	
	;integer comparison
	cmp dx, si ;both args are in upper half
	sbb ax, ax ;set dx to 1 if cf is set
	push_num_to_op_stack ax
	ret
	 
.fp:
	call op_cast_args_to_fp
	
	 ;first arg = dx:ax
	 ;second arg = si:cx

	 
	cmp ax, cx
	sbb dx, si ;we're done here
	 
	
	clc
	jnl .no_set ;set dx to 1 if cf (less than)
	stc
	.no_set:
	sbb ax, ax
	push_num_to_op_stack ax
	ret	
	
op_sub:
	xor di, di
	call op_get_arg
	mov cx, ax ;backup second arg to cx
	mov si, dx ; incase it is fixed
	rcl di, 1
	
	cmp bx, op_stack ;only one argument?
	jz .negate ;yep
	
	call op_get_arg
	rcl di, 1
	test di, 0b11
	jnz .fp
	
	;integer addition
	sub dx, si ;both args are in upper half
	push_num_to_op_stack dx
	ret
	 
.fp:
	call op_cast_args_to_fp

	sub ax, cx
	sbb dx, si ;32 bit subtraction
	
	push_fp_to_op_stack
	
	
	ret
.tmp_fp_store: dw 0	
.negate:
	test di, 0b10
	jnz .negate_fp ;bit is on
	neg dx
	push_num_to_op_stack dx ;push it back to stack
	ret
.negate_fp:
	neg dx
	neg ax
	sbb dx, 0
.skip_negate_bottom:
	push_fp_to_op_stack
	
	ret

op_int: ;casts arg to num
	call op_get_arg
	jnc .skip_cast
	
	push bx
	push di
	call div_32_by_1000
	pop di
	pop bx
	
	mov dx, ax
.skip_cast:
	push_num_to_op_stack dx
	ret
	
op_lb: ;casts arg to num
	call op_get_arg
	
	jc .skip_int
	mov ax, dx
	mov dx, 1000
	mul dx
.skip_int:	

	;input = dx:ax
	push bx
	push di
	call log2
	pop di
	pop bx
	
	push_fp_to_op_stack
	ret
	
	
	
op_eb: ;casts arg to num
	call op_get_arg
	
	jc .skip_cast
	
	mov si, .sin_msg
	mov bx, 0
	int 0xff
	return_after_error
	
.sin_msg: db "EB requires a fixed point argument",0
	
.skip_cast:	

	;input = dx:ax
	push bx
	push di
	call exp2

	pop di
	pop bx
	
	push_fp_to_op_stack
	ret

op_sin: ;casts arg to num
	call op_get_arg
	
	jc .skip_cast
	
	mov si, .sin_msg
	mov bx, 0
	int 0xff
	return_after_error
	
.sin_msg: db "SIN requires a fixed point argument",0
	
.skip_cast:	

	;input = dx:ax
	push bx
	push di
	call cordic_sin


	pop di
	pop bx
	
	push_fp_to_op_stack
	ret
	
op_sqrt: ;casts arg to num
	call op_get_arg
	
	jc .skip_cast
	
	mov si, .sin_msg
	mov bx, 0
	int 0xff
	return_after_error
	
.sin_msg: db "SQRT requires a fixed point argument",0
	
.skip_cast:	

	;input = dx:ax
	push bx
	push di
	
	mov bl, 0
	mov byte [direct_sqrt_port.in_lo], 0xff
	call direct_sqrt_port
	jmp $

	pop di
	pop bx
	
	push_fp_to_op_stack
	ret
	
	
op_bxor:
	op_get_two_args
	test di, 0b11
	jnz .fp
	
	;integer addition
	xor dx, si ;both args are in upper half
	push_num_to_op_stack dx
	ret
	 
.fp:
	call op_cast_args_to_fp
	
	 ;first arg = dx:ax
	 ;second arg = si:cx
	 
	xor ax, cx
	xor dx, si ;we're done here
	 
	push_fp_to_op_stack
	ret
	
op_band:
	op_get_two_args
	test di, 0b11
	jnz .fp
	
	;integer addition
	and dx, si ;both args are in upper half
	push_num_to_op_stack dx
	ret
	 
.fp:
	call op_cast_args_to_fp
	
	 ;first arg = dx:ax
	 ;second arg = si:cx
	 
	and ax, cx
	and dx, si ;we're done here
	 
	push_fp_to_op_stack
	ret
	
op_bor:
	op_get_two_args
	test di, 0b11
	jnz .fp
	
	;integer addition
	or dx, si ;both args are in upper half
	push_num_to_op_stack dx
	ret
	 
.fp:
	call op_cast_args_to_fp
	
	 ;first arg = dx:ax
	 ;second arg = si:cx
	 
	or ax, cx
	or dx, si ;we're done here
	 
	push_fp_to_op_stack
	ret
	
op_add:

	op_get_two_args

	test di, 0b11
	jnz .fp

	;integer addition
	add dx, si ;both args are in upper half
	push_num_to_op_stack dx
	ret
	 
.fp:
	call op_cast_args_to_fp
	
	 ;first arg = dx:ax
	 ;second arg = si:cx
	 
	
	add ax, cx
	adc dx, si ;we're done here
	 
	push_fp_to_op_stack
	ret

op_mod:
op_get_two_args
	test di, 0b11
	jnz .fp
	
	;divide by zero check
	test si, si
	jz op_divide_by_zero
	
	;integer division
	mov cx, si ;both args are in upper half
	mov ax, dx ;can't use dx as it will be used in multiply
	xor dx, dx ; zero it for correct result
	
	div cx ;divide si (in ax) with cx

	push_num_to_op_stack dx ;remainder in dx
	ret
	 
.fp:

	
	call op_cast_args_to_fp
	
	push bx

	mov bp, cx


	;divide by zero check
	
	test si, si
	jnz .skip_dz_fp
	test bp, bp
	jz op_divide_by_zero ;it is zero
	
.skip_dz_fp:
	
	call div_32

	mov dx, di
	mov ax, bx ;move remainder to dx:ax
	
	
	pop bx
	
	
	push_fp_to_op_stack
	


	ret





op_div:
	op_get_two_args
	
	test di, 0b11
	jnz .fp
	
	;divide by zero check
	test si, si
	jz op_divide_by_zero
	
	;integer division
	mov cx, si ;both args are in upper half
	mov ax, dx ;can't use dx as it will be used in multiply
	xor dx, dx ; zero it for correct result
	
	div cx ;divide si (in ax) with cx

	push_num_to_op_stack ax
	ret
	 
.fp:

	
	call op_cast_args_to_fp
	
	push bx

	mov bp, cx


	;divide by zero check
	
	test si, si
	jnz .skip_dz_fp
	test bp, bp
	jz op_divide_by_zero ;it is zero
	
.skip_dz_fp:
	
	push si
	push bp
	
	;mul by 1000 first
	mul_by_1000_to_48 dx, ax
	
	;mov dx, si
	;mov ax, bp
	mov [div_48_2.tmp_48_storage], bx ;temporarily store it there
	
	pop bp 
	pop si
	

	
	call div_48_2
	
	
	pop bx
	
	
	push_fp_to_op_stack
	


	ret

op_divide_by_zero:
	mov si, .dbz_str
	xor bx, bx
	int 0xff
	jmp op_error_handling

.dbz_str: db "Division by zero",10,0
	
	
op_abs:
	call op_get_arg 
	jc .fp_abs
	
	;magic branchless abs
	xchg ax, dx ;exchange high and low bits
	cwd ;get mask
	xor ax, dx
	sub ax, dx
	push_num_to_op_stack ax
	ret
	
.fp_abs:
	test dx ,dx
	jns .skip_neg
	
	neg dx
	neg ax
	sbb dx, 0
.skip_neg:
	push_fp_to_op_stack
	ret
op_mul:
	op_get_two_args
	test di, 0b11
	jnz .fp
	
	;integer multiplication
	mov ax, si ;both args are in upper half
	mul dx ;multiply si (in ax) with dx

	;xor dx, dx
	mov dx, 1000
	mul dx
	
	push_fp_to_op_stack ;need more precision 
	ret
	 
.fp:
	
	call op_cast_args_to_fp
	

	push bp
	push bx

	mov bp, cx
	
	call mul_32
	
	;debug_print_32 si,bp
	;debug_print_32 fdx,ax
	
	
	call div_64_by_1000
	mov dx, si
	mov ax, bp
		
	
	pop bx
	
	
	push_fp_to_op_stack
	
	pop bp


	ret

op_ptr: ;question mark, used to peek and poke mem
	
	call op_get_arg
	jnc .ptr_err
	
	push_op_stack_16 dx
	push_op_stack_16 ax
	push_op_stack_8 TOK_PTR
	ret
.ptr_err:
	mov si, .not_ptr_str
	xor bx, bx
	int 0xff
	return_after_error

.not_ptr_str: db "? only takes a fixed point number as pointer", 0
	jmp $
	
op_pow:
	
	op_get_two_args
	test di, 0b11
	jnz .fp
	
	;cx = first arg (input)
	 ; si = sec arg (exp)
	 ;ax = result
	 mov ax, 1
	
	mov cx, dx
	xor dx, dx
	
	test si, si ;skip when b is 0
	jz .skip_int_pow
;fast exp algo
.int_pow_loop:
	test si,1
	jz .skip_mult_res
	mul cx ;result = result * a(cx)
.skip_mult_res:
	shr si, 1 ;b/=2
	
	xchg ax, cx
	push dx
	mul ax
	pop dx
	xchg ax, cx
	
	test si, si
	jnz .int_pow_loop

.skip_int_pow:

	push_num_to_op_stack ax
	
	ret
.fp:
	;dx:ax = input
	;si:cx = exponent
	
	jcxz .no_fp_pow
	test si, si
	jz .no_fp_pow
.fp_pow_loop:	
	test cx, 1
	jz .no_mult_result
	

.no_mult_result:
	shr si, 1
	rcr cx, 1
	
	test cx, cx
	jnz .fp_pow_loop
	test si, si
	jnz .fp_pow_loop
	
.no_fp_pow:
	
	ret
	
op_ass:
	call op_get_arg
	pushf
	
	push ax
	push dx
	
	op_assert_nonempty_stack
	pop_op_stack_8 cl ;get id token
	cmp cl, TOK_PTR
	jz .set_ptr
	cmp cl, TOK_ID ;is it an id token
	jnz op_error_handling ;nope we have an err
	
	
	
	push di
	mov si, [bx] ;peek op stack
	push bx
	call varman_find_var
	pop bx
	mov ax, si
	pop di
	

	jnc .skip_decl
	mov si, [bx] ;peek stack
	
	xchg bx, ax
	cmp byte [bx], TOK_IDX
	jz .no_arr
	xchg bx, ax
	
	call varman_decl_var

.skip_decl:

	pop_op_stack_16 si ;get pointer to id token string


	pop dx
	pop ax

	popf 

	
	jc .set_fixed
	mov cl, TOK_NUM
	mov ax, dx
	;we still have si 

	call varman_set_var
	
	push_num_to_op_stack ax

	ret
.set_fixed:
	mov cl, TOK_FP ; data type = FP
	;data already in DX:AX
	
;	debug_print [basic_var_ptr]

	call varman_set_var
		
	push_fp_to_op_stack 
	
	ret
.set_ptr:
	pop dx
	pop ax
	
	mov ax, es
	pop_op_stack_16 di
	pop_op_stack_16 es

	popf 
	jc op_error_handling
	;data 
	mov [es:di], dl
	
	xor dh, dh
	push_num_to_op_stack dx
	
	mov es, ax
	
	ret
.no_arr:
	mov si, .no_arr_str
	xor bx, bx
	int 0xff
	return_after_error
.no_arr_str: db "Nonexistent array",0

op_tab: ;starts from token 3
	dw op_ass,
	dw 0xdead,
	dw op_bor,
	dw op_eb,
	dw 0xdead,
	dw 0xdead,
	dw 0xdead,
	dw 0xdead,
	dw 0xdead,
	dw 0xdead,
	dw 0xdead,
	dw 0xdead,
	dw op_sqrt,
	dw op_less,
	dw 0xdead,
	dw 0xdead,
	dw 0xdead,
	dw op_add,
	dw op_sub,
	dw op_sin,
	dw 0xdead,
	dw op_mul,
	dw op_div,
	dw op_mod,
		dw op_abs,
		dw op_pow,
		dw 0xdead,
		dw 0xdead,
		dw 0xdead,
		dw 0xdead,
		dw 0xdead,
		dw op_lb
		dw op_int,
		dw op_ptr,
		dw 0xdead,
		dw 0xdead,
		dw 0xdead,
		dw 0xdead,
		dw 0xdead,
		dw 0xdead,
		dw 0xdead,
	
	
	





%IF 0

autonum TOK_EMPTY_VAR
autonum TOK_FP
autonum TOK_ASS  ;ASSIGNMENT operator
autonum TOK_LOR 
autonum TOK_BOR
autonum TOK_LXOR 
autonum TOK_BXOR
autonum TOK_LAND 
autonum TOK_BAND 
autonum TOK_ID 
autonum TOK_NUM 
autonum TOK_EQ 
autonum TOK_NEQ 
autonum TOK_COMMA;is operator`
autonum TOK_SQRT  ;top precedence
autonum TOK_LESS 
autonum TOK_MORE 
autonum TOK_LEEQ 
autonum TOK_MOEQ 
autonum TOK_ADD 
autonum TOK_SUB  
autonum TOK_SIN  ;top precedence
autonum TOK_COS  ;top precedence
autonum TOK_MUL 
autonum TOK_DIV 
autonum TOK_MOD 
autonum TOK_ABS  ;top precedence
autonum TOK_POW  ;over this = top 
autonum TOK_BNOT 
autonum TOK_MINUS  
autonum TOK_NOT
autonum TOK_CLOSBRACKET
autonum TOK_OPENBRACKET 
autonum TOK_RSVD
autonum TOK_INT 
autonum TOK_PTR   ;everything beyond this are not operators
autonum TOK_CLEAR 
autonum TOK_IDX
autonum TOK_QUOTE ; STRING CONSTANT
autonum TOK_GOTO 
autonum TOK_LIST 
autonum TOK_PRINT 
autonum TOK_INPUT 
autonum TOK_RUN
autonum TOK_IF
autonum TOK_THEN
autonum TOK_ELSE
autonum TOK_GOSUB
autonum TOK_RETURN
autonum TOK_DIM
autonum TOK_END 
autonum TOK_IDXEND

%ENDIF
