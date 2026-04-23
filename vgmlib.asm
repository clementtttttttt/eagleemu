vgm_step:
	mov ax, datSeg
	mov ds, ax
	
	mov ax, [ds:music_pointer]
	test ax, ax
	jz .start_playback
	
	cld ;up
	mov si, ax
	
	
	mov ax, 0xc000
	mov es, ax
		
.loop:
	
	cs lodsb
	
	cmp al, 0xbd
	jnz .wait

	cs lodsw ;get data to write and value
	
%ifdef EFFECTS_SUPPORT
	push ax
	and al, 0b111
	cmp al, EFFECTS_CHANNEL ;ah = effects channel
	pop ax
	jz .loop
	
	cmp al,  EFFECTS_CHANNEL >> 1 + 0x10
	jz .loop
%endif
	
	mov [es:3], al;write reg addr
	mov [es:2], ah;write reg data 
	
	cs lodsb
	
	cmp al, 0xbd
	jnz .wait

	cs lodsw ;get data to write and value
	
%ifdef EFFECTS_SUPPORT
	push ax
	and al, 0b111
	cmp al, EFFECTS_CHANNEL ;3 = effects channel
	pop ax
	jz .loop
	cmp al, EFFECTS_CHANNEL >> 1 + 0x10
	jz .loop
%endif
	
	
	mov [es:3], al;write reg addr
	mov [es:2], ah;write reg data 
	
	jmp .loop ;process more commands
	
.wait:
	cmp al, 0x62
	jnz .loop_playback ; unknown command, restart
 ;1 frame delay, do nothing
 	mov ds:[music_pointer], si ;store it back


	ret
	
.start_playback:
	mov ax, cs:[music_file+0x34] ;data offset
	add ax, music_file + 0x34;offset relative to stream
	mov ds:[music_pointer], ax ;store into music pointer


	ret
	
.loop_playback:
	mov ax, cs:[music_file+0x1c] ;data offset
	test ax, ax
	jz .start_playback
	add ax, music_file + 0x1c;offset relative to stream
	mov ds:[music_pointer], ax ;store into music pointer
	ret


vgm_vsync:

	
	push ax
	push es
	push si
	push ds

	call vgm_step
	
	pop ds
	pop si
	pop es
	pop ax
	iret
