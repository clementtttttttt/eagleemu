#include "gfx.h"
#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <stdlib.h>
extern uint32_t* screen;
uint32_t ptr;
uint8_t vram[32768];

int in_vblank;

void gfx_reset_ptr() {
    ptr = 0;

}

void gfx_init_vram(){
    for(int i=0;i<32768;++i){
        vram[i] = rand();
    }
}

void gfx_clear(){
    memset(screen, 0, 320*480*4);
    for(int i=0;i<320*480/8;++i){
        for(int j=0;j<8;++j){
            if(vram[i] & (1 << j)){
                screen[ptr] = 0xffffffff;
            }
            else{
                screen[ptr] = 0;
            }
            ++ptr;


        }
    }
}
extern int dbgsync;
extern pthread_mutex_t intsync;

extern uint16_t delay;
extern volatile int nodelayint;

uint8_t* gfx_get_addr(uint16_t addr){
	dbgsync = 1;
	nodelayint = 1;
	if(!in_vblank){
		delay += 20;
	}
	dbgsync = 0;

    return &vram[addr];
}
