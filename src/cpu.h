void* system_func();
char* cpu_dump_debug();
char* cpu_dump_flags_debug();

#include <stdint.h>

enum{
    ax,cx,dx,bx,sp,bp,si,di

};

enum{
    es,cs,ss,ds

};

void cpu_reset();

union flags_t{
    uint16_t raw;

    struct{

        uint16_t c : 1;
        uint16_t rh1 : 1;
        uint16_t p : 1;
        uint16_t r : 1;
        uint16_t a : 1;
        uint16_t r1 : 1;
        uint16_t z: 1;
        uint16_t s : 1;
        uint16_t t : 1;
        uint16_t i : 1;
        uint16_t d : 1;
        uint16_t o : 1;
        uint16_t rh2: 1;
        uint16_t rh3: 1;
        uint16_t rh4 : 1;
        uint16_t rh5 : 1;
    };


}__attribute__((packed));

void cpu_hw_start_int (uint8_t vec);
void cpu_step();
unsigned char cpu_get_debug_reg();
