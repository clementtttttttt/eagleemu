
%include "operators/operators.asm"



print_22_10: ;helper routine for printing 22:10 fp, input dx:ax
	push di
	
	TEST DX, DX
	jns .no_sign
	push ax
	mov al, '-'
	push bx
		mov bx, 3
	int 0xff
	pop bx
	pop ax
	
	neg dx
	neg ax
	sbb dx, 0 ;twos complement

.no_sign: 

	call div_32_by_1000 ;divide
	
	push bx
	mov bx, 4
	int 0xff ;print dividend
	
	
	mov al, '.'
	mov bx, 3 ;print decimal 
	int 0xff
	pop bx
	
	mov ax, bx ;remainder
	
	
	mov bx, 1 ;we're done here
	int 0xff
	
	pop di
	ret
	

st_print:
	mov al, ' ' ;print space
	push bx
	mov bx, 3
	int 0xff
	
	pop bx
	
	test byte [di], 0xff ;test if it's 0
	jz .end_print
	
	cmp byte [di], TOK_QUOTE ; is it a string that we're looking at 
	jz .string_print
	
	cmp byte [di], TOK_ELSE ;else = end of line
	jz .end_print

	call parse_exp ;parse_exp should return a 22.10 number
	
	call print_22_10
	
	
	jmp st_print
.end_print:
	mov al, 10
	push bx 
	mov bx, 3
	int 0xff
	pop bx ; print newline
	ret
.string_print:
	;skip over quote
	inc di
	
	mov al, [di] ; get current character
	cmp al, TOK_QUOTE
	jz .break_print_loop
	push bx ;print it
	mov bx, 3
	int 0xff
	pop bx
	jmp .string_print
.break_print_loop:
	
	
	INC DI ;skip quote
	cmp BYTE [di], TOK_COMMA ;skip comma
	jnz st_print
	inc di ; skip the token
	jmp st_print
	
	
st_gosub:
	mov bx, [prog_stack_ptr] ;current program stack pointer
	sub bx, 2 ;push stuff
	mov [bx], di ;old pointer wrte into stack
	add word [bx], 3 ; add offset of 3 (gosub number token in front)
	mov [prog_stack_ptr], bx ;write into stack pointer
	
	jmp st_goto ;goto new line pointer 

	
	
st_end:
	return_after_error
	
st_return:
	mov bx, [prog_stack_ptr] ;get stack pointer
	cmp bx, prog_stack
	jae .err
	
	mov di, [bx] ;restore from stack
	add bx, 2
	mov [prog_stack_ptr], bx
	ret
	
.err:
	mov si, .err_str
	xor bx, bx
	int 0xff
	return_after_error
.err_str: db "Subroutine stack empty",0	
	
	
	
st_goto:
	cmp byte [di], TOK_NUM ;is it a number
	jnz .goto_err
	
	inc di
	
	mov ax, [di] ;get line number
	
	add di, 2
	cmp word [di], 0; end of line?
	jnz .goto_err ;nope, err
	
	mov cx, di ;keep end of line in cx
	
	xor dx, dx

	
	;line number now in ax, we need to search for the line in basic_mem
	
	mov di, basic_mem
	
	.line_search:
	cmp word [di], ax ;is it a match
	jz .end
	
	call find_end_of_line
	jmp .line_search
	.end:
	
	add di, 2;skip over line number
	
	ret
.goto_err:
	mov si, .goto_no_line_err_str
	xor bx, bx
	int 0xff
	return_after_error

.goto_no_line_err_str: db "Nonexistent line number",0


st_input:

	push di
	push bx
	
	mov di, line_buf ;we store input at line_buf
	call getline
	
	mov si, line_buf
	call atoi
	
	debug_print ax
	
	pop bx
	pop di
	
		;now at tok_id
	cmp byte [di], TOK_ID
	jnz .input_err
	
	ret
.input_err:
	mov si, .input_err_str
	xor bx, bx
	int 0xff
	return_after_error
.input_err_str: db "INPUT syntax error",0

;push constant into token stack	

st_num:
	mov ax, [di] ;get number
	add di, 2 ;skip over number
	
	mov bx, [op_stack_ptr]
	
	push_op_stack_16 ax
				
	mov [op_stack_ptr], bx
			
	ret

st_clear:
	xor sp, sp ;pop off return address
	cli
	jmp reset_language ;reset almost everything

st_id:  ;jump here when start of expression is id

	dec di
	
	call parse_exp
	
	ret
	
st_run:
	push di
	
	mov di, basic_mem ;change di to basic mem for interpretation
	;reset basic var
	
	mov ax, [basic_buf_end]
	mov [basic_var_ptr],ax
	mov word [basic_var_sz], 0
	
.loop:
	cmp word [di], 0 ;is line number 0?
	jz .quit ;yep job done
	
	add di, 2 ;skip over line number
	call interpret_line
	
	jmp .loop
	.quit:
	
	pop di
	ret
	
st_dim:
	
	
	cmp byte [di], TOK_ID
	jnz .not_id
	mov si, di ;si = TOK_ID location
	
	inc di 
	mov cl, [di] ;get count
	inc di
	xor ch, ch
	add di, cx ;skip it
	
	cmp byte [di], TOK_NUM
	jnz .not_id
	
	inc di
	mov dx, [di] ;get array count
	add di, 2
	
	
	mov al, [di]
	cmp al, TOK_INT ;int array?
	
	jnz .skip_set_int
	inc di ;skip tok_int
	mov al, TOK_NUM
	
.skip_set_int:
	test al, al
	jnz .skip_set_fp
	
	mov al, TOK_FP
	
.skip_set_fp:

	
	call varman_decl_arr
	;call varman_dump_vars
	
	ret
		
.not_id:
	mov si, .not_id_err
	xor bx,bx 
	int 0xff
	return_after_error
.not_id_err: db "usage: DIM [ID] [SZ] (INT)",0

st_else:
	call find_end_of_line
	ret ;go to end

st_if:
	call parse_exp ;test if expression is true
	
	test dx, dx
	jz .run_else ;not true
.continue:
	;skipped then token already
	ret ;interpret_line treats ELSE as end of line
	
.run_else:
	test ax, ax
	jnz .continue ; ax not empty
	
.find_else:
	mov al, TOK_ELSE
	SUB DI, 2 ;subtract offset used for func
	call search_line_for_token
	
	cmp byte [di-1], TOK_ELSE ;is thre an else token
	jz .skip_fix
	;di now at address after token
	
	;note: we're at the end of the line and we need to fix thte pointer so that it points to the quad zero token
	sub di, 4
	;jmp $
.skip_fix:
	ret

st_list:
	push di ;preserve token pointer
	
	mov di, basic_mem; set to buf
	xor bh, bh ; wont need bh 
	
	jmp .start_list_loop ;compensate for increment
.list_loop:
	add di, 4 ;skip zeroes
	mov al, 10 
	push bx
	mov bx, 3
	int 0xff
	pop bx
.start_list_loop:
	cmp di, [basic_buf_end]
	jae .return ;exit after we reached end
	
	mov ax, [di]; get line number from start of line	
	test ax, ax ;count is 0, end list
	jz .return
	
	push bx
	mov bx, 1
	int 0xff
	pop bx
	
	add di, 2 ;skip to the tokens
.iterate_toks:
	
	mov al, ' ' ;print space to seperate keywords
	push bx
		mov bx, 3
	int 0xff
	pop bx

	mov al, [di] ;get token
	test word [di], 0xffff
	jnz .definitely_not_end
	test word [di+2], 0xffff ;four zeroes found
	jz .list_loop ; end of line, next line
	.definitely_not_end:
	
	cmp al, TOK_ID
	jz .print_id
	
	cmp al, TOK_QUOTE
	jz .print_quotes

	cmp al, TOK_FP
	jz .print_fp

	cmp al, TOK_NUM
	jnz .not_number
	

	
	inc di
	mov ax, [di] ;number is after token
	push bx
	mov bx, 1
	int 0xff
	
	
	pop bx
	
	add di, 2 ;skip over the number
	jmp .iterate_toks
.print_quotes:
	push bx
	; change to si since lodsb needed
	mov al, '"'
	mov bx, 3
	int 0xff ;print quotes
	
	inc di ;set to strss
	mov si, di
	.print_loop:
	lodsb
	cmp al, TOK_QUOTE ; is it quote
	jz .break_print_loop
	mov bx, 3
	int 0xff
	test al, al
	jnz .print_loop ; definitely not end
	cmp word [si+1], 0
	jnz .print_loop
	cmp word [si+3], 0
	jz .break_print_loop ;found four zeroes
	
	jmp .print_loop
	.break_print_loop:
	
		mov al, '"'
	mov bx, 3 ;print quotes
	int 0xff
	
	mov di, si ;store si back
	pop bx
	
	jmp .iterate_toks
.print_fp:
	inc di ; skip token
	
	mov dx, [di]
	add di, 2
	mov ax, [di]	
	add di,2 ;next token
		
	call print_22_10

	jmp .iterate_toks
	
	
.print_id:
	inc di
	mov cl, [di] ; get string/id len
	xor ch, ch
	inc di
	mov si, di ;clone to si since putstrig accepts parameter in si
	add di, cx ; advance di beforehand
	mov dl, al ;backup al (token) in dl
	call putstring_cx ;print it
	jmp .iterate_toks
	
.not_number:
	mov si, keywords_to_tok ; set to table
.cmp_tab:
	mov cl, [si] ;get len of comp string
	test cl, cl ;zero len = end of table
	jz .chk_num ;end of table
	inc si
	xor ch,ch ;zero ah
	add si, cx
	mov al, [si] ; set al to token in entry
	cmp al, [di] ;compare current token
	jnz .goto_next_tab_ent
	push si
	sub si, cx ; gotten token match 
	call putstring_cx ;
	pop si

	
	inc di ;next token
	jmp .iterate_toks
	
.goto_next_tab_ent: 
	inc si
	jmp .cmp_tab

.return:
	

	pop di
	
	ret
.chk_num:
	cmp byte [di], TOK_NUM
	jnz .list_error_no_ent ;not number
	inc di
	mov ax, [di]
	
	push bx
	mov bx, 1
	int 0xff ; print number
	pop bx
	
	mov al, ' '
	push bx
	mov bx, 3
	int 0xff ; print space
	pop bx
	jmp .iterate_toks
	
.list_error_no_ent:
	mov si, .list_err
	xor bx, bx
	int 0xff
	mov al, [di]
	cbw ;zero ah
	mov bx, 2
	int 0xff
	pop di
	jmp beforegetline

.list_err: db 10,"LIST: no table entry for func: ",0


;returns 22:10 result in dx:ax 
parse_exp: ;start of expression	
	mov word [op_stack_ptr], op_stack ;reset stack ptr
.recurse:
	mov bx, [op_stack_ptr]
	mov ax, bx
	push_op_stack_16 ax
	mov word [op_stack_ptr], bx
.exp_loop:
	mov al, [di] ;get token to al


	test al, al
	jz .not_operator_end_parse; end of expression(0)
	
	
	cmp byte al, TOK_NUM ;is it a number
	jz .push_num ; push it into arguments stack
	cmp byte al, TOK_FP
	jz .push_fp
	cmp byte al, TOK_ID ;is it an ID
	jz .push_var ; yes check variables
	cmp al, TOK_IDXEND
	jz .not_operator_end_parse_comma
	cmp al, TOK_COMMA
	jz .not_operator_end_parse_comma
	
	call get_precedence ;test if it's an operator 
	jc .not_operator_end_parse_comma ;not an operator if carry is on
	
	
	op_run_func
.not_operator_end_parse_comma:
	inc di
	
.not_operator_end_parse:	 
	cmp bx, op_stack ; is stack empty
	jz .parse_err_stack_empty ;yes, err
	
	pop_op_stack_8 al ;pop off token from stack for comparison

	
	; pop off result from stack
	cmp byte al, TOK_NUM ; is the token a number
	jz .get_from_num
	
	cmp byte al, TOK_FP
	jz .get_from_fp ;s the token an fp number
	
	cmp byte al, TOK_ID
	jz .get_from_id

	cmp byte al, TOK_PTR
	jz .get_from_ptr

	jmp .return_point
.get_from_id:
	pop_op_stack_16 si ;get pointer to id token
	call varman_get_var
	cmp cl, TOK_FP
	jz .return_point ;no casting needed
	cmp cl, TOK_NUM
	jz .get_id_num
	
	
	jmp $
.get_from_fp:

	pop_fp_from_op_stack
	
	jmp .return_point	
.get_from_ptr:
	mov dx, es
	pop_op_stack_16 si
	pop_op_stack_16 es
	mov al, [es:si]
	xor ah, ah
	mov es, dx
	jmp .get_id_num
.get_from_num:
	
	
	pop_op_stack_16 ax
	
.get_id_num:
	
	mov dx, 1000
	
	mul dx ;we're done here
	
	
.return_point:
	add bx, 2 ;pop

	cmp bx, [bx-2] ; is stack empty
	jnz .parse_err ;no, err
	
	mov [op_stack_ptr], bx
;	inc di ; increment current token index
	ret
.parse_err:

	xor sp,sp ; pop off return addr
	mov si, .parse_err_msg
	xor bx, bx
	int 0xff
	jmp beforegetline ;abort
.parse_err_msg db "More than one argument in stack",0
.parse_err_empty_stack_msg db "Empty return argument in stack",0
.parse_err_stack_empty:
	xor sp, sp
	mov si, .parse_err_empty_stack_msg
	xor bx, bx
	int 0xff
	jmp beforegetline
	

.push_var:
	push_op_stack_16 di ;push pointer to entire id token
	inc di 
	mov al, [di] ; get count
	xor ah, ah ; clear upper count
	inc di ; increment to string start
	
	add di, ax ; skip string
	push_op_stack_8 TOK_ID

	mov [op_stack_ptr], bx ; save stack ptr


	cmp byte [di], TOK_IDX ;is there an array index 
	jz .push_arr_id
	
	
	jmp .exp_loop
.push_arr_id:

	
	inc di
	call parse_exp.recurse ;recurse AND SKIP TO index end

	
	jmp .exp_loop

	
	
.push_fp:
	inc di ;skip token
	cld
	xchg si, di
	
	lodsw ; set first two bytes
	push_op_stack_16 ax
	
	lodsw ; set post two bytes
	 ;inc to next
	xchg si, di

	push_op_stack_16 ax
	push_op_stack_8 TOK_FP
	
	mov [op_stack_ptr], bx ; save stack ptr
	
	jmp .exp_loop
	
.push_num:
	inc di ;increment token buf pointer to numbers
	mov ax, [di] ; get number
	add di, 2 ; skip the number

	push_num_to_op_stack ax
	
	mov [op_stack_ptr], bx ; save op stack pointer
	
	jmp .exp_loop

	
