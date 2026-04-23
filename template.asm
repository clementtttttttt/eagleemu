use16
cpu 8086

org 0xe000:0
start:

mov bx, 0xc000
mov ds, bx
xor ax, ax

%include "iolib.asm"

resb 0x20000 - 0x10- ($-$$)

reset_start:
jmp 0xe000:0

resb 0x20000-($-$$)

