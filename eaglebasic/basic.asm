LBUF_LEN equ 1024
LINE_TOKS_B equ 512
OP_STK_SZ equ 256
PROG_STK_SZ equ 512
%macro pusha_v20 0
db 01100000b ; nec v20 pusha instruction
%endmacro
%macro popa_v20 0
db 01100001b ; nec v20 pusha instruction
%endmacro
%macro return_after_error 0
	xor sp, sp
	jmp beforegetline
%endmacro


%macro debug_print_32 2
	pusha_8088
	pushf
	
	
	mov ax, %2
	mov dx, %1
	
	push si
	push ax
	push dx
	
	mov si, %%dbg_msg
	xor bx, bx
	int 0xff
	
	pop dx
	pop ax
	pop si
	
			
	mov bx, 4
	int 0xff
	
	
	mov al, 10
	mov bx, 3
	int 0xff
		
	popf
	popa_8088
	jmp %%dbg_end
%%dbg_msg db %str(%1),':',%str(%2), '=',0
%%dbg_end:

%endmacro


%macro pusha_8088 0
push ax
push bx
push cx
push dx
push si 
push di
push bp
%endmacro

%macro popa_8088 0
pop bp
pop di
pop si
pop dx
pop cx
pop bx
pop ax
%endmacro

%macro autonum_debugprint 1
	%1 equ dp_id
	%assign dp_id dp_id+1
%endmacro

%define dp_id 1 


%macro debug_print 1
	pusha_8088
	pushf
		mov ax, %1

	push ax
	push si
	mov si, %%msg
	xor bx, bx
	int 0xff
	pop si
	pop ax
	
	mov bx, 2
	int 0xff
	
	mov al, 0xa
	MOV BX, 3
	int 0xff

	jmp %%msg_end
	%%msg: db %str(%1),'=',0
	%%msg_end:
	
	popf
	popa_8088
%endmacro 


;upper 16 bits at bx
;input = dx:ax
%macro mul_by_1000_to_48 2
push si

xchg cx, ax
mov ax, dx
mov dx, 1000
mul dx

mov bx, dx
mov si, ax

xchg cx, ax

mov dx, 1000
mul dx

add dx, si
adc bx, 0


pop si


%endmacro


%macro debug_print_8 1
	pusha_8088
	pushf
	
	pusha_8088
	mov si, %%msg
	xor bx, bx
	int 0xff
	popa_8088
	
	xor ah, ah
	mov al, %1
	mov bx, 2
	int 0xff
	
	mov al, 0xa
	mov bx, 3
	int 0xff

	jmp %%msg_end
	%%msg: db %str(%1),'=',0
	%%msg_end:
	popf
	popa_8088
%endmacro 

%macro debug_print_message 1
	pusha_8088
	pushf
	mov si, %%msg
	xor bx, bx
	int 0xff
	
	jmp %%msg_end
	%%msg: db %1,0
	%%msg_end: 
	mov al, 10
	mov bx, 3
	int 0xff
	popf
	popa_8088
%endmacro

%macro debug_print_string_addr 1
	pusha_8088
	pushf
	mov si, %1
	xor bx, bx
	int 0xff
	
	mov al, 10
	mov bx, 3
	int 0xff
	popf
	popa_8088
%endmacro

%macro debug_print_string_addr_cx_eff 2
	pusha_8088
	pushf
	lea si, %1
	mov cl, %2
	xor ch, ch
	call putstring_cx
	
	mov al, 10
	mov bx, 3
	int 0xff
	popf
	popa_8088
%endmacro



start:

call iolib_setup

;setup segs
mov ax, ds
mov es, ax

;set stack pointer
xor sp, sp

;clear dir flag
cld

;empty line buf
mov di, line_buf
mov cx, LBUF_LEN/2
xor ax, ax
rep stosw


mov si, init_str
xor bx, bx
int 0xff


;calculate mem that we have
mov ax, 0xffff
sub ax, basic_mem
mov [mem_avail], ax

mov bx, 1
int 0xff

reset_language:


mov word [basic_var_ptr], basic_mem
mov word [basic_var_sz], 0 ;zero it
mov word [basic_buf_end], basic_mem
mov word [prog_stack_ptr], prog_stack

;empty basic mem
mov di, basic_mem
mov cx, [mem_avail]
xor ax, ax
rep stosb

beforegetline:
cli
mov al, 10 ;newline
mov bx, 3
int 0xff
mov al, '>' ;prompt
mov bx, 3
int 0xff

cld
;empty line
mov di, line_buf
mov cx, LBUF_LEN/2
xor ax, ax
rep stosw



mov di, line_buf ;we store input at line_buf

call getline

mov al, 10
push bx
mov bx, 3
int 0xff
pop bx

tokeniser:

mov word  [op_stack_ptr], op_stack ;initialise op stack pointer

;empty tokbuf
mov di, tokenise_buf
mov cx, LINE_TOKS_B+4;four zeroes
xor ax, ax
rep stosb



mov si, line_buf 
mov bx, tokenise_buf ;tokenise buf  pointer

.tokeniser_cmp_loop_match:
mov di, keywords_to_tok ;set di to table pointer
.tokeniser_cmp_loop:

call skip_space
test byte [si], 0xff ;are we at the end of a line (si is zeroo
jz .end_tokeniser

mov cl, [di] ;set counter to length
xor ch,ch 	;zero top of counter
test cl,cl
jz .tokeniser_check_number ;out of stirngs, check if it's a number

inc di ; skip len byte
call cmp_str
jnz .skip_equ ;not equ

mov al, [di];get token for precedence and checks

; we can use di at this point since it'll be reset anyway when we jump back
mov di, [op_stack_ptr]
call get_precedence ;check if the token is an operator PLUS get precedence of it
jnc .tokeniser_op_shunting_yard

;empty operator stack since end of expression (not operator)
.empty_stack:
cmp di, op_stack
jz .skip_empty ;stack is empty (di = op_stack)
call op_stack_pop
mov [bx], cl ;store to token buf
inc bx ; increment 
jmp .empty_stack
.skip_empty:
mov [op_stack_ptr], di
mov [bx], al ;set bx (tokenise buf pointer) to token
inc bx ;incrment tokenise buf pointer


cmp al, TOK_QUOTE ;is it string opening
jz .op_is_quote ;yes

jmp .tokeniser_cmp_loop_match ;we have a match

.tokeniser_op_shunting_yard:

cmp dl, 0xff ; is it infinite precedence
jz .break_op_pop_loop ;yes, push it
cmp al, TOK_COMMA ;test if token (al) is comma
jz .op_is_comma
cmp al, TOK_CLOSBRACKET ;test if token is closbracket
jz .op_is_cb

.op_pop_loop:
cmp  di, op_stack
jz .break_op_pop_loop ;stack  is empty
cmp byte [di], TOK_OPENBRACKET ; o2 is not a left parentheiss
jz .break_op_pop_loop


xchg dh, dl ; backup dl on dh
xchg ah, al ; backup al on ah
mov al, [di] ; get the token in stack
call get_precedence ;get precedence of token on stack
xchg ah, al ; revert backup (current token)


cmp dl, dh ; and o2 (dl = stack top rpecedence) has a greater precedence 
ja .no_break
jne .break_op_pop_loop ;OR equal precedence than o1(dh) AND o1 left associative
cmp al, TOK_POW ;power is RIGHT associative
jz .break_op_pop_loop ;break
cmp al, TOK_ASS ;ass is also right associative
jz .break_op_pop_loop
.no_break:

xchg dh, dl ; restore dh and dl 

call op_stack_pop
mov [bx], cl ;store into token pointer
inc bx ; increment token buf pointer
mov [op_stack_ptr], di
jmp .op_pop_loop

.break_op_pop_loop:

; push current token 
dec di ; decrement stack pointer to store
;current token in AL, store to stack ptr address
mov [di], al

;store updated stack pointer
mov [op_stack_ptr], di
jmp .tokeniser_cmp_loop_match

.op_is_cb: ;!!!! sshared section with comma

.op_is_comma:

mov cl, [di] ;get stack top and check if it's openbracket


cmp cl, TOK_OPENBRACKET ;while not open bracket
jz .break_comma_loop ;quit it if it is
cmp al, TOK_COMMA
jnz .skip_nostack_check
cmp di, op_stack
jnz .skip_nostack_check ;dont run that  if stack is empty
mov [bx], al ;put comma into queue in order ot implement comma lists
inc bx
jmp .skip_cb_sec
.skip_nostack_check:
call op_stack_pop
mov [bx], cl ; pop
inc bx
jmp .op_is_comma
.break_comma_loop:

cmp al, TOK_COMMA ; compare current token to comma
jz  .skip_cb_sec ;is a comma, skip this cb-only section

call op_stack_pop ;pop and ignore CB
cmp di, op_stack
jz .skip_cb_sec ;empty stack no funcs to pop
mov cl, [di]
call is_function ;c flag equals true  
jnc .skip_cb_sec ;not function, skip function handling
call op_stack_pop
mov [bx], cl ; set token buf vlaue
inc bx ; increment token buf pointer

.skip_cb_sec:
mov [op_stack_ptr], di

jmp .tokeniser_cmp_loop_match

.skip_equ:
inc di ;skip token byte
jmp .tokeniser_cmp_loop ;we do NOT have a match

.end_tokeniser:
;end of the line
;pop out all the tokens from the operator stack
mov di, [op_stack_ptr]

.pop_all_op:
cmp di, op_stack
jae .end_pop_all_op ;stack empty
call op_stack_pop
cmp cl, TOK_OPENBRACKET ;open bracket in stack = incomplete pair
jz .tokeniser_bad_ob_err
mov [bx], cl ; store token in current position
inc bx
jmp .pop_all_op
.end_pop_all_op: 

.line_number_check:
mov cx, bx ;back bx in cxs
mov bx, tokenise_buf ;read from tokenised buf


cmp BYTE [bx], TOK_NUM ; is the first token a number (LINE NUMBER) 
jnz .imm ;not a line number, interpret the line

add bx,3 ; skip token 
mov ax, [bx-2] ;get line number
test ax, ax
jz .imm ; treat as imm if line number is zero


; AT THIS POINT:
; CX = SOURCE TOK BUF END
; AX = DESTINATION LINE NUMBER TO INSERT TO

add cx, 4 ;add four zeroes

push cx ; preserve it
mov di, basic_mem

.find_line:
	cmp di, [basic_buf_end]
	jae .copy_tokbuf_to_line_setend

	cmp ax, [di] ;compare line number against current line
	jz .old_line_same_as_new
	jb .line_insert ; current line number is below the  one in memory 
	
	call find_end_of_line
	jmp .find_line
	
.line_insert:
	;start of line above in di, we want to move it out of the way
	push di ;save it for copying from tokbuf to basic_mem
	push cx ;save for same purpose above as well
	std ;downwards move
	
	sub cx, tokenise_buf + 1 ;get length of line in tok_buf minus its number token

	mov ax, di ;backup start of current line in basic_mem
	mov si, [basic_buf_end];get end of basic_buf
	mov di, si ;clone in di
	add di, cx ;add top by current line size
	mov [basic_buf_end], di ;save new basic_buf top 
	
	mov cx, si ;get old basic_buf_end in cx to calculate copy count
	sub cx, ax;old basic_buf_end - start_of_current_line_in_basic_mem
	
	inc cx; just for good measure
	
	rep movsb ; c o p y 

	pop cx
	pop di
	
	;we are done here
	jmp .copy_tokbuf_to_line

.old_line_same_as_new:
	mov dx, di ; backup start of line
	push di
	call find_end_of_line
	
	mov bx, cx ;backup end of line in tok_buf
	sub bx, tokenise_buf+1 ;bx = length of line in tok_buf plus line number
	
	mov si, di ;will need end of basic_mem line later
	sub di, dx ;di = length of line in basic_mem 
	
	sub bx, di ;bx = length of line in tok_buf - length of line in basic_mem
	
	
	js .move_down ;negative difference need to move down
.move_up:

	std ;movsb direfction down
	
	mov cx, [basic_buf_end]
	mov di, cx ;need the same value in di as well	
		
	sub cx, si 	 ;count = old_basic_buf_end-end_of_line_in_basic_mem
	inc cx ; magic fix to everything
	
	mov si, di ;same value as di (old_basic_buf_end at this point)
	add di, bx ;add old basic_buf_end pointer wiht offset

	mov [basic_buf_end], di ;store new basic_buf_end 
	rep movsb ;copy

	jmp .copy
.move_down:
	cld ;movsb direction up
	
		
	neg bx ;negate it
	
	;si already has end of basic_mem line
	mov di, si ;clone it
	sub di, bx ;subtract difference from di
	mov cx, [basic_buf_end] ;end of basic_buf in cx
	sub cx, si ;subtract cx with source to get count
	
	sub [basic_buf_end], bx ;subtract difference to basic_buf_end too	
	
	rep movsb ;copy first
	
	push ax
	push di
	push cx
	
	xor al, al ;zero space after being moved

	mov di, [basic_buf_end] ;end to data buffer in basic_buf_end

	mov cx, bx;get count in cx
	
	cld ; up
	
	rep stosb ;zero it
	
	pop cx
	pop di
	pop ax
	jmp .copy


	
.copy_tokbuf_to_line_setend:
mov bx, sp; poke stack
mov cx, [ss:bx]
sub cx, tokenise_buf+1 ;get length
add [basic_buf_end], cx
push di


.copy:	
	
pop di

.copy_tokbuf_to_line:

pop cx

call varman_move_buf ;update variable storage location


cld


sub cx, tokenise_buf+ 1; subtract tokenise buf AND first two bytes (two byte number of number token)
mov si, tokenise_buf+ 1 ;same point
;di already gotten

rep movsb ;copy


.skip_set_buf:


jmp beforegetline
.imm:

mov di, bx
call interpret_line ;interpret the current line (moved pointer to di from bx)


jmp beforegetline

.tokeniser_check_number:

call atoi
jz .tokeniser_variable ;not number, probably identifier

cmp byte [si], '.' ; is there a comma after
jz .op_is_fp ; fixed point code 

;token IS a number
;just put it on the tokenise buf since we're doing shunting yard

mov byte [bx], TOK_NUM ;number token
inc bx ;increment token buffer pointer
mov [bx], ax ;store the number
add bx, 2; skip over number
jmp .tokeniser_cmp_loop_match ;we DO have a match

.op_is_fp:

;push op as fp

inc si ; skip over point

mov byte [bx], TOK_FP; fixed point
inc bx ; increment pointer

push si
push bx
mul_by_1000_to_48 dx, ax
pop bx
pop si

mov cx, ax ;backup ax in cx

;multiplied by 1000


push di


;get length of number for multiply 
mov di, si

push dx

call atoi ;get lower fraction
push si

;should be 1000 based
cmp ax, 1000
jae .tokeniser_fp_err

sub si, di ;length
mov dx, 3
sub dx, si ;3-length

jz .skip_mul
.mul_by_10:
	shl ax, 1
	mov di, ax
	shl di, 1
	shl di, 1
	add ax, di
	
	dec dx
	jnz .mul_by_10
.skip_mul:

pop si
pop dx

pop di


add cx, ax
adc dx, 0 ;32 bit add


mov [bx], dx
add bx, 2
mov [bx], cx ;write the stuff
add bx, 2

;debug_print_32 dx, cx


;next token
jmp .tokeniser_cmp_loop_match

.op_is_quote:
cld
mov di, bx ;set copy destination to tokenise buf
;si set by tokeniser
.str_copy_loop:
cmp byte [si], '"'
jz .break_str_copy
cmp byte [si], 0
jz .tokeniser_string_err
movsb
jmp .str_copy_loop
.break_str_copy:
mov bx, di ; set it back to bx
mov byte [bx], TOK_QUOTE ; end quote
inc bx
inc si ;skip over quote
jmp .tokeniser_cmp_loop_match

.tokeniser_variable:
mov byte [bx], TOK_ID ; id token
inc bx
call get_id_len

jcxz .tokeniser_syntax_err

push cx
add cx,bx
sub cx, tokenise_buf
cmp cx, LINE_TOKS_B
pop cx

ja .tokeniser_lbuf_err

mov [bx], cl ;set id string length (1 byte)
inc bx ;skip over string length count

mov di, bx
repe movsb ;copy over string
mov bx, di
jmp .tokeniser_cmp_loop_match

.tokeniser_fp_err:
mov cx, 5
jmp .tokeniser_syntax_err
.tokeniser_string_err:
mov cx, 4
jmp .tokeniser_syntax_err
.tokeniser_bad_ob_err:
mov cx, 3
jmp .tokeniser_syntax_err
.tokeniser_op_stack_underflow_err:
mov cx, 2
jmp .tokeniser_syntax_err
.tokeniser_lbuf_err:
mov cx, 1
.tokeniser_syntax_err: ;cx will be zero 
call error
return_after_error




;detects if operator is function
;cl = input
; CF = is function
is_function:
	cmp cl, TOK_SQRT
	jz .is
	cmp cl, TOK_ABS
	jz .is
	cmp cl, TOK_SIN
	jz .is
	cmp cl, TOK_COS
	jz .is
	cmp cl, TOK_INT
	jz .is
	cmp cl, TOK_LB
	jz .is
	cmp cl, TOK_EB
	jz .is

	
	cmp cl, 35 ;anything over 35 is probably a function FIXME
	ja .is
		
	clc
	ret
	.is:
	stc
	ret

;di = stack pointer
;cl = return
op_stack_pop:
	cmp di,op_stack
	jae .stack_underflow
	mov cl, [di] ;get form top of stack
	inc di
	ret
.stack_underflow:
	add sp, 2 ; pop off return address
	jmp tokeniser.tokeniser_op_stack_underflow_err ;we are at the top of stack

;di = in
find_end_of_line:
	push ax
	add di, 2 ;skip line number
.find_loop:
	mov ax, [di]
	test WORD ax, 0xffff
	jnz .not_end
	test WORD [di+2], 0xffff
	jnz .not_end
	
	add di, 4
	pop ax
	ret ;we found the end
.not_end:
	cmp byte al, TOK_NUM
	jz .add_num_off
	cmp byte al, TOK_FP
	jz .add_fp_off
	inc di
	jmp .find_loop
	
.add_num_off:
	add di, 3
	jmp .find_loop


.add_fp_off:
	add di, 5
	jmp .find_loop	
	
;di = in, set to address after token
;al = token to find
;cx = idx stack level
search_line_for_token:
	add di, 2 ;skip line number
	xor cx, cx
.find_loop:
	

	cmp BYTE [di], al
	jz .found_tok
	
	test WORD [di], 0xffff
	jnz .not_end
	test WORD [di+2], 0xffff
	jnz .not_end

	
	
	add di, 4
	ret ;we found the end
.not_end:
	cmp byte [di], TOK_IDX
	jnz .skip_idx
	inc cx
.skip_idx:
	cmp byte [di], TOK_IDXEND
	jnz .skip_idxend
	dec cx
.skip_idxend:
	cmp byte [di], TOK_NUM
	jnz .skip_add_num_off
	add di, 3
	jmp .find_loop
.skip_add_num_off:
	cmp byte [di], TOK_FP
	jnz .skip_add_fp_off
	add di, 5
	jmp .find_loop
.skip_add_fp_off:
	inc di
	jmp .find_loop
.found_tok:
	cmp al, TOK_IDXEND
	jnz .not_idxend_end
	test cx, cx
	jnz .skip_idx
	
.not_idxend_end:

	inc di ;address after token
	ret
	

;si = id location, updated to end
;cx = id len
get_id_len:
	push bx
	mov bx, si
.loop:
	mov al, [si]
.compare_upper_case:
	cmp al, 'A'
	jb .not_upper_case
	cmp al, 'Z'
	ja .not_upper_case
	jmp .valid_character
.not_upper_case:
	cmp al, 'a'
	jb .not_lower_case
	cmp al, 'z'
	ja .not_lower_case
	jmp .valid_character
.not_lower_case:
	cmp al, '0'
	jb .not_number
	cmp al, '9'
	ja .not_number
	jmp .valid_character
.not_number:
	cmp al, '_'
	jz .valid_character
	jmp .end_id
.valid_character:
	inc si
	jmp .loop
.end_id:
	mov cx, si
	sub cx, bx ;get count
	mov si, bx ;restore original si
	pop bx
	ret

;di = line with tokens
interpret_line:

sti ;enable interrupts to get escape key

cmp di, [basic_buf_end]
jae .end_of_line ;out of bounds

mov al, [di]
test al, al
jz .might_be_zero ;two zeroes
.definitely_not_zero:
mov bl, al; store current token in al for op hckec
call get_precedence ;is it a part of an expression

jc .not_operator

call parse_exp

jmp interpret_line
.not_operator:

xor bh, bh ;get current token and zero bh for table
sub bl, TOK_CLEAR  ; subtract index by 35 since tbale doesnt have those lwoer index

shl bx, 1; multiply index since table entry size is 2 bytes
 ;token to funciton table
mov ax, [bx+tok_to_func] ;ax = tok_to_func[bx], bx is token
cmp ax, 0xdead
jz .interp_tok_no_func_err
;increment token pointer
inc di
call ax ; call the function pointer

jmp interpret_line

.end_of_line:
add di, 4 ;expected to leave line pointer at end of line

cli

ret
.might_be_zero:
test word [di], 0xffff
jnz .definitely_not_zero
test word [di+2], 0xffff ;token is 0, end of line 
jz .end_of_line
jmp short .definitely_not_zero

.err_msg db "INTERP: func not implemented: ",0
.interp_tok_no_func_err:
mov si, .err_msg
push bx
xor bx, bx
int 0xff
pop bx
shr bx, 1
mov ax, bx
mov bx, 1
int 0xff


ret


;cx = errcode
error:
mov si, error_tab
jcxz .after_loop
.get_err_msg_loop:
xor al,al
cld
xchg di, si
.find_zero: 
scasb
jnz .find_zero
xchg si, di
loop .get_err_msg_loop

.after_loop:
xor bx, bx
int 0xff ;si would be message

ret

putstring_cx:
	mov bx, 3
	push cx
	lodsb
	push si
	int 0xff
	pop si
	pop cx
	loop putstring_cx
	ret
error_tab:
	db "Mistake",0
	db "Token buffer overflow",0
	db "Operator stack underflow",0
	db "Incomplete parentheses pair",0
	db "Incomplete doublequotes pair", 0
	db "Decimal tokenisation error",0

;al = token
;cf = not operator
;dl = priority (higher better)
get_precedence: 
	cmp al, TOK_FP ;TOK_ASS = least ipmortant operator
	jb .not_operator
	cmp al, TOK_PTR ;TOK_PTR = most important operator
	ja .not_operator

	cmp al, TOK_OPENBRACKET
	jae .top_precedence ; operators with values over TOK_OPENB all have the same precedence 
	
	push cx
	mov cl, al
	call is_function ; check if it's a function
	pop cx
	jc .top_precedence
	
	mov dl, al
	
	shr dl, 1 ;divide by 2
	shr dl, 1 ;divide by 2 again (operator precedence = vaue divided by 4)
	
	clc 
	
	ret
.top_precedence:
	mov dl, 0xff
	clc
	ret
.not_operator:
	stc
	ret
	

;si = input
;di = input2
;cx = count

;zf = is_equal
;si = char after match if match
cmp_str:
	mov dx, si
	rep cmpsb
	jz .no_restore_si
	mov si, dx
	.no_restore_si:
	pushf
	add di, cx
	popf
	ret

dbgstr db "DEBUG PRINT MATCH", 0

%macro autonum 1
	%1 equ s_id
	%assign s_id s_id+1
%endmacro

%define s_id 1

autonum TOK_EMPTY_VAR
autonum TOK_FP
autonum TOK_ASS  ;ASSIGNMENT operator
autonum TOK_LOR 
autonum TOK_BOR
autonum TOK_EB 
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
autonum TOK_LB
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


tok_to_func:

	dw st_clear
	dw 0xdead
	dw 0xdead
	dw st_goto
	dw st_list
	dw st_print
	dw st_input
	dw st_run
	dw st_if
	dw 0xdead
	dw st_else
	dw st_gosub
	dw st_return
	dw st_dim
	dw st_end
        times 256-35-($-tok_to_func)/2 dw 0xdead
keywords_to_tok:
	db 1, "+", TOK_ADD
	db 1, "-", TOK_SUB
	db 1, "*", TOK_MUL
	db 1, "/", TOK_DIV
	db 1, "^", TOK_POW
	db 1, "=", TOK_ASS
	db 1, ",", TOK_COMMA
	db 1, "%", TOK_MOD
	db 1, "(", TOK_OPENBRACKET
	db 1, ")", TOK_CLOSBRACKET
	db 1, "[", TOK_IDX
	db 1, "]", TOK_IDXEND
	db 1, ">", TOK_MORE
	db 1, "<", TOK_LESS 
	db 1, "|", TOK_BOR
	db 1, "&", TOK_BAND
	db 3, "EOR", TOK_BXOR
	db 2, "==", TOK_EQ
	db 1, "?", TOK_PTR
	db 5, "PRINT", TOK_PRINT
	db 5, "INPUT", TOK_INPUT
	db 3, "INT", TOK_INT
	db 5, "GOSUB", TOK_GOSUB
	db 4, "GOTO", TOK_GOTO
	db 6, "RETURN", TOK_RETURN
	db 4, "LIST", TOK_LIST
	db 3, "ABS", TOK_ABS
	db 2, "LB", TOK_LB
	db 2, "EB", TOK_EB
	db 3, "SIN", TOK_SIN
	db 3, "COS", TOK_COS
	db 3, "DIM", TOK_DIM
	db 4, "SQRT", TOK_SQRT
	db 1, '"', TOK_QUOTE
	db 5, "CLEAR", TOK_CLEAR
	db 3, "RUN", TOK_RUN
	db 2, "IF", TOK_IF
	db 4, "THEN", TOK_THEN
	db 4, "ELSE", TOK_ELSE
	db 3, "END", TOK_END
	db 3, "NOT", TOK_NOT
	db 0
;si = input
;si = first non space char
skip_space:
	mov al, 32; ascii space
	cld
	.loop:
	cmp [si], al
	jnz .out_loop
	inc si
	jmp .loop
	.out_loop:
	ret



;converts str to digit terminated by non digi
;si = input string
;ax = output
;si output = first non number char
;zf = notnumber
;dx = upper bits
atoi:
	push bx
	push cx
	mov bx, si ;get original si value
	xor cx, cx
	xor dx, dx
	push bx
		
.atoi_loop:
	mov al, [si]
	sub al, '0'
	cmp al, 9 ; not valid if difference is larger than nine  
	ja .term
	inc si
	xor ah,ah ;set ah to 0 because we dont need
	
	shl cx, 1 ; cx = 2cx
	rcl dx, 1 ;shift it over to upper bits
	
	push dx
	mov bx, dx  ; copy in bx with high bits (dx)
	mov dx, cx ;copy dx for add 
	shl dx, 1 ;dx = 8cx
	rcl bx, 1 ; shift top bit over
	shl dx, 1
	rcl bx, 1 ;shift top bit over again
	
	add cx, dx
	
	pop dx ;restore dx (high bits of cx)

	adc dx, bx ;add with carry 

	add cx,ax
	adc dx, 0 ;account for carry
	jmp .atoi_loop
.term:

	pop bx
	cmp si, bx
	mov ax, cx; get lower bits
	; get z flag
	jnz .no_restore
	mov si, bx ;only restroe when z flag is not set
.no_restore:
	
	pop cx
	pop bx
	ret


;di=linebuf
getline:
	mov bx, di ;backup
.getline_loop:
	call keytest	
	cmp al, 8 ;backspace
	jnz .skip_backspace
	cmp di, bx ;is it the beginning
	jz .getline_loop
	dec di ;backspace to prev pos
	mov byte [di], 0 ;change to 0	
	jmp .skip_all
	.skip_backspace:
	
        push bx
        add bx,LBUF_LEN-1 ;do we still have space
        cmp di, bx
        pop bx
	jae .end_getline
	
	cld; str go up
	stosb

	cmp al, 10 ;test lf
	jz .end_getline	
	
	.skip_all:
	cmp al, 8 ;backspace
	jz .print_backspace
	push bx
	mov bx, 3
	int 0xff
	pop bx
	jmp .getline_loop
.end_getline:
	dec di
	mov byte [di], 0 ; replace lf with 0
	ret
.print_backspace:
	push bx
	mov bx, 3
	int 0xff
	
	mov al, ' '
	mov bx, 3
	int 0xff
	
		mov al, 8
	mov bx, 3
	int 0xff
	pop bx
	jmp .getline_loop

key_callback:
	cmp al, 27 ;escape
	jnz .no_match
	xor sp, sp;reset stack
	
	;reset segments
	mov ax, datSeg
	mov ds, ax
	mov es, ax
	

	;call clear_screen

	xor ax, ax ;zero in ax
	push ax ;push flags
	mov ax, codeSeg ;segment
	push ax
	mov ax, beforegetline
	push ax
	

	iret ;return
	
.no_match:
	ret

mem_avail dw 0 
;basic memory goes up to 0xffff of current segmen

%include "statements.asm"
%include "varalloc.asm"

%define USE_SERIAL

%define USE_KEY_CALLBACK
%include "../bioslib.asm"
%include "../mathlib.asm"


op_stack_ptr: dw 0

init_str db "EAGLE-88 BASIC v0.30",10,"COPYRIGHT 2024 CLEMENT",10,"MEM AVAILABLE: ",0
basic_buf_end: dw 0
basic_var_sz: dw 0
basic_var_ptr: dw 0 ;start of basic variables
prog_stack_ptr: dw 0

align 32
end:
op_stack equ end+OP_STK_SZ ;stack of one byte operator tokens
line_buf equ op_stack
prog_stack equ line_buf+LBUF_LEN+PROG_STK_SZ
tokenise_buf equ prog_stack+2
imm_buf equ tokenise_buf+LINE_TOKS_B+4
basic_mem equ imm_buf+LINE_TOKS_B+4

;tokenise_buf: resb LINE_TOKS_B+4
;imm_buf: resb LINE_TOKS_B
;
;basic_mem: 

