org 0
cpu 8086
;cpu 186

db "SG"
dw end_f-start_f
dw 0
dw codeSeg

start_f:

start:



end_f:

align 2; align to boundary

db "RN"
dw start
dw codeSeg
