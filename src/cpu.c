#include "cpu.h"
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <pthread.h>
#include <stdio.h>
#include "gfx.h"
#include "keyb.h"
#include "8255.h"
#include "serial.h"
#include "saa1099_ext.h"
#include "pcr.h"
#include "sd.h"
#include <string.h>
#include <errno.h>

#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/signal.h>

uint8_t* memory;
uint8_t *rom;

volatile int dbgsync;

volatile uint16_t ip;
uint16_t regs[8] = {0,0,0,0,0,0,0,}; //ax cx dx bx sp bp si di
uint16_t none = 0;
union flags_t flags_reg= {.r1 = 1, .r=1,.rh1 = 1, .rh2 = 1, .rh3=1, .rh4=1, .rh5=1};

uint32_t segregs[4]; //es,cs,ss,ds

uint8_t segfault = 0;

uint8_t pcreg = 0;

char mmuen = 0;
uint64_t ticks = 0;


enum{
    regptr, offset8, offset16, reg

};

uint16_t mmio_buf = 0;
uint32_t mmio_access_addr = 0;

uint16_t delay;

uint8_t low, high;

static uint8_t cpu_debug_reg = 0;

unsigned char cpu_get_debug_reg(){

    return cpu_debug_reg;
}



uint8_t enable_rep;


static inline short signex_8(char in){
    uint16_t m = in;
    m = m | (0-(m&0x80));
    return m;

}

void cpu_rep(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    //no ip decrement to go to next instruction in
    enable_rep = 1 + (opcode & 1);
    delay += 9;
}
static inline uint8_t* memgetptr(uint32_t addr){
    delay += 4; //no wait state system

    addr &= 0xfffff;
    if((low > (addr >> 12) || (addr>>12) > high) && mmuen){
         segfault =1;
    }

    if((addr >> 17)  == 0b111){
        return &rom[addr&0x1ffff];
    }
    if((addr >> 17) == 5){

        return gfx_get_addr(addr & 0x7fff);
    }
    if((addr >> 17) == 6){

        mmio_access_addr = addr;
        switch(addr & 0xffff){
            case 0:
                mmio_buf = cpu_debug_reg;
            break;
            case 1:
                mmio_buf = sd_get_shiftreg();
            case 2:
                //mmio_buf = *saa1099_get_addr();
             //saa1099 does not support reads
            break;
            case 3:
                //saa1099 does not uspport reads
         //       mmio_buf = *saa1099_get_addr();
            break;
            case 4:
                mmio_buf =* (uint8_t*)i8255_get_reg((pcreg >> 1) & 0b11);
            break;
            case 5:
                mmio_buf = *(uint8_t*)keyb_get_shiftreg();
            break;

            case 8:
            case 9:
            case 0xa:
            case 0xb:
            case 0xc:
            case 0xd:
            case 0xe:
            case 0xf:

                mmio_buf=*(serial_get_regs(addr & 0b111));
            break;

        }


        return (uint8_t*)&mmio_buf;


    }
    if((addr >> 17) <= 2){
        return &memory[addr];
    }

    none = 0;
    return (uint8_t*)&none;
}
static inline uint8_t memread(uint32_t addr){
    addr &= 0xfffff;
    if(addr == 0xc0008) return *((uint8_t*)serial_get_regs(0));
    return *memgetptr(addr);

}
static inline void memwrite(uint8_t in, uint32_t addr){
    addr &= 0xfffff;

    if((addr>>17)  == 6){
        switch(addr & 0xffff){
            case 0:
                cpu_debug_reg = in;
            break;
            case 1:
                pcreg = in;
                sd_tick(pcreg >> 3);

            case 3:
                *(saa1099_get_addr()) = in;
            break;
            case 2:
                saa1099_ext_write_data(in);




            break;
            case 4:
                * (uint8_t*)i8255_get_reg((pcreg >> 1) & 0b11) = in;
            break;
            case 5:
                // (uint8_t*)keyb_get_shiftreg();
                //return (uint8_t*) keyb_get_shiftreg();
            break;
            case 6:
                low = in;
            break;

            case 7:
                high = in;
            break;

            case 8:
            case 9:
            case 0xa:
            case 0xb:
            case 0xc:
            case 0xd:
            case 0xe:
            case 0xf:
                serial_write_regs((unsigned char)addr, in);
            break;

        }
        return;

    }



    uint8_t *p = memgetptr(addr);



    if((p != (uint8_t*)&none) && (addr >> 17) != 0b111) *p= in;
    if(addr >> 17 == 0b111) {
    printf("%s %x %x\n", "ATTEMPTING TO WRITE TO ROM AT", segregs[cs], ip);
    dbgsync=1;
    cpu_dump_debug();
    }

}


static void stack_push(uint16_t in){
    regs[sp] -= 2;

        memwrite(in&0xff, regs[sp]+segregs[ss]*0x10);
        memwrite(in>>8, regs[sp]+1+segregs[ss]*0x10);


}
static  uint16_t memread16(uint32_t addr){
    uint16_t ret;

    ret = (memread(addr) |  memread(addr+1)<<8);
    delay -= 4;

    return ret;

}


void set_flags16(uint16_t result){
    uint16_t par = result;
    par ^= par >> 8;
    par ^= par >> 4;
    par ^= par >> 2;
    par ^= par >> 1;

    flags_reg.p = !!(((~par) & 1)); //Par
    flags_reg.z = ((result == 0)); //Zero
    flags_reg.raw |= result  & 0b1000; // AC flag
    flags_reg.s = !!(result & 0x8000);
}

void set_flags8(uint8_t result){
    uint8_t par = result;
    par ^= par >> 4;
    par ^= par >> 2;
    par ^= par >> 1;

    flags_reg.p = !!(((~par) & 1)); //Par
    flags_reg.z = (result == 0); //Zero

    flags_reg.raw |= result  & 0b1000; // AuxCarry flag
        flags_reg.s = !!(result & 0x80);
}

void set_add_cf_of16(uint8_t setcarry, uint16_t sec, uint16_t first, uint8_t carry){
        uint32_t carrycheck = sec + first + carry;

        if(setcarry)
        flags_reg.c = !!(carrycheck & 0x10000);
        flags_reg.raw |= ((sec^carrycheck)&(first^carrycheck)&0x8000)?(1 << 11):0; //OF


}
void set_add_cf_of8(uint8_t setcarry, uint16_t sec, uint16_t first, uint8_t carry){
        uint32_t carrycheck = sec + first + carry;

        if(setcarry)
        flags_reg.c = !!(carrycheck & 0x100);
        flags_reg.raw |= ((sec^carrycheck)&(first^carrycheck)&0x80)?(1 << 11):0; //OF


}
void set_sub_cf_of8(uint8_t setcarry, uint16_t sec, uint16_t first, uint8_t c){
        uint32_t carrycheck = (sec&0xff) -(first&0xff) - c;

        if(setcarry){
        flags_reg.c = !!(carrycheck & 0x100) ;

        }
                carrycheck = (sec&0x7f) - (first&0x7f) - c;

        flags_reg.o = flags_reg.c ^ !!(carrycheck & 0x80);


}
void set_sub_cf_of16(uint8_t setcarry, uint16_t sec, uint16_t first , uint8_t c){
        uint32_t carrycheck = sec - first - c;

        if(setcarry){
        flags_reg.c = !!(carrycheck & 0x10000) ;
        }

        carrycheck = (sec&0x7fff) - (first&0x7fff) - c;
        flags_reg.o = flags_reg.c ^ !!(carrycheck & 0x8000);


}

void cpu_add(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode&1){
        set_add_cf_of16(1,*sec,*first,0);

        *sec += *first;


        set_flags16(*sec);

    }
    else
    {
               set_add_cf_of8(1,*sec,*first,0);

        *(unsigned char*)sec += *(unsigned char*)first;
        set_flags8(*sec);

    }
    delay += 3;
}
void cpu_aadd(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    if(opcode& 1){
        uint16_t read =  (((uint16_t)modrm) | ((uint16_t)(memread(++ip + segregs[cs]*0x10) <<8)));
        set_add_cf_of16(1,regs[0],read,0);

        regs[0] += read;
        set_flags16(regs[0]);
    }
    else{
         uint8_t read =  modrm;
        set_add_cf_of8(1,regs[0]&0xff,read,0);

        *(uint8_t*)&regs[0] += read;
        set_flags8(regs[0]);

    }
    delay += 4;
}

void cpu_sub(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode&1){
        set_sub_cf_of16(1,*sec,*first,0 );

        *sec -= *first;


        set_flags16(*sec);

    }
    else
    {
               set_sub_cf_of8(1,*sec,*first,0);

        *(unsigned char*)sec -= *(unsigned char*)first;
        set_flags8(*sec);

    }
    delay += 3;

}

void cpu_aadc(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    if(opcode& 1){
        uint16_t read =   (((uint16_t)modrm) | ((uint16_t)(memread(++ip + segregs[cs]*0x10) <<8)));
        set_add_cf_of16(1,regs[0],read,flags_reg.c);

        regs[0] += read;
        regs[0] += flags_reg.c;
        set_flags16(regs[0]);
    }
    else{
         uint8_t read =  modrm;
        set_add_cf_of8(1,regs[0]&0xff,read,(flags_reg.c));

        *((uint8_t*)&regs[0]) += read;
                *((uint8_t*)&regs[0]) += flags_reg.c;
        set_flags8(regs[0]);

    }
}
void cpu_and(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode&1){

        *sec &= *first;


        set_flags16(*sec);
    }
    else
    {

        *((unsigned char*)sec) &= *((unsigned char*)first);
        set_flags8(*sec);

    }

    flags_reg.raw &= ~(1);
    flags_reg.raw &= ~(1<<11);


}
void cpu_atest(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    uint16_t tmp;
    if(opcode&1){

        tmp = ((uint16_t)modrm | (memread(++ip + segregs[cs]*0x10)<<8))& regs[0];

        set_flags16(tmp);

    }

    else
    {

        tmp = modrm & (unsigned char)regs[0];
        set_flags8(tmp);
    }

    flags_reg.raw &= ~(1);
    flags_reg.raw &= ~(1<<11);


}
void cpu_test(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    uint16_t tmp;
    if(opcode&1){

        tmp = *sec & *first;

        set_flags16(tmp);

    }
    else
    {

        tmp = (*(unsigned char*)sec) & (*(unsigned char*)first);
        set_flags8(tmp);

    }


    flags_reg.c = 0;
    flags_reg.o = 0;

}
void cpu_aand(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode&1){

        regs[0] &=( ((uint16_t)modrm) | (((uint16_t)memread(++ip + 0x10*segregs[cs])) << 8));


        set_flags16(regs[0]);

    }
    else
    {

        *(unsigned char*)&regs[0] &= modrm;
        set_flags8(regs[0]);

    }

    flags_reg.raw &= ~(1);
    flags_reg.raw &= ~(1<<11);


}
void cpu_xor(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode&1){

        *sec ^= *first;



        set_flags16(*sec);

    }
    else
    {

        *(unsigned char*)sec ^= *(unsigned char*)first;
        set_flags8(*sec);

    }

    flags_reg.c = 0;
    flags_reg.o = 0;
    delay += 3;

}

void cpu_axor(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode&1){

        regs[0] ^=( ((uint16_t)modrm) | (((uint16_t)memread(++ip + 0x10*segregs[cs])) << 8));


        set_flags16(regs[0]);

    }
    else
    {

        *(unsigned char*)&regs[0] ^= modrm;
        set_flags8(regs[0]);

    }

    flags_reg.raw &= ~(1);
    flags_reg.raw &= ~(1<<11);


}

static uint16_t effaddr;

void cpu_or(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode&1){

        *sec |= *first;


        set_flags16(*sec);

    }
    else
    {

        *(unsigned char*)sec |= *(unsigned char*)first;
        set_flags8(*sec);

    }

    flags_reg.raw &= ~(1);
    flags_reg.raw &= ~(1<<11);

    delay += 3;
}

void cpu_aor(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode&1){

        regs[0] |=( ((uint16_t)modrm) | (((uint16_t)memread(++ip + 0x10*segregs[cs])) << 8));


        set_flags16(regs[0]);

    }
    else
    {

        *(unsigned char*)&regs[0] |= modrm;
        set_flags8(regs[0]);

    }
    delay += 4;

    flags_reg.raw &= ~(1);
    flags_reg.raw &= ~(1<<11);


}



void cpu_adc(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    uint8_t cf = flags_reg.c;
    if(opcode& 1){

        set_add_cf_of16(1,*sec,*first,cf);

        *sec += *first + cf;


        set_flags16(*sec);
    }
    else{
               set_add_cf_of8(1,*sec,*first,cf);

        *(unsigned char*)sec += *(unsigned char*)first + cf;
        set_flags8(*sec);

    }

    delay += 3;
}


void cpu_jmp8(uint16_t *first, uint16_t *sec, char modrm, uint8_t opcode){
    short test = signex_8(modrm);
    ip += test;
}

void cpu_call16(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    short off = modrm;
    *(((unsigned char*)&off)+1) = memread(++ip + segregs[cs]*0x10);

    stack_push(ip);
    ip += off;
}

void cpu_jmp16(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    short off = modrm;
    *(((unsigned char*)&off)+1) = memread(++ip + segregs[cs]*0x10);

    ip += off;
}

void cpu_farjmp(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    uint16_t ip_v = modrm;
    ip_v |= (memread(++ip + segregs[cs]*0x10) << 8);
    uint16_t cs_v = memread(++ip + segregs[cs]*0x10);
    cs_v |= (memread(++ip + segregs[cs]*0x10) << 8);
    segregs[cs] = cs_v;
    ip = ip_v;
    --ip;
}

void cpu_sbb(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    unsigned char fc = flags_reg.c;
    if(opcode&1){
        set_sub_cf_of16(1,*sec,(*first), fc);

        *sec -= (*first+fc);


        set_flags16(*sec);

    }
    else
    {
               set_sub_cf_of8(1,*sec,(*first), fc);

        *(unsigned char*)sec -= (*(unsigned char*)first + fc);
        set_flags8(*sec);

    }
    delay += 3;
}
void cpu_asub(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    uint16_t first16;
    if(opcode&1){
        set_sub_cf_of16(1,regs[0],first16=(modrm | (memread(++ip + segregs[cs]*0x10) << 8)), 0);

        regs[0] -= first16;


        set_flags16(regs[0]);

    }
    else
    {
               set_sub_cf_of8(1,regs[0],modrm, 0);

        *((unsigned char*)&regs[0]) -= modrm;
        set_flags8(regs[0]);

    }
    delay += 4;
}

void cpu_asbb(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    uint16_t first16;
    unsigned char fc = flags_reg.c;
    if(opcode&1){
        set_sub_cf_of16(1,regs[0],first16=((modrm | (memread(regs[++ip + segregs[cs]*0x10])))), fc);

        regs[0] -= (first16+fc);


        set_flags16(regs[0]);

    }
    else
    {
               set_sub_cf_of8(1,regs[0],modrm,fc);

        *(unsigned char*)&regs[0] -= (modrm+fc);
        set_flags8(regs[0]);
    }
        delay += 4;

}


uint16_t seg_override=0;

void cpu_seg_override(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;


    seg_override = ((opcode >>3 )& 3) + 1;


}

void cpu_daa(){
    --ip;
    uint8_t old_al = regs[0] &0xff;
    uint8_t old_cf = flags_reg.raw & 1;
    flags_reg.raw &= ~1;
    if((regs[0]&0xf) >=10 || flags_reg.raw & 0x10){
        uint16_t low = (regs[0] & 0xff) + 6;
        *(unsigned char*)&regs[0] = low&0xff;
        flags_reg.raw |= (old_cf || low & 0x1ff);
        flags_reg.raw |= 0x10;


    }
    else{
        flags_reg.raw &= ~(0x10);
    }
    if((old_al) > 0x99 || old_cf){
        *(unsigned char*)&regs[0] = *(unsigned char*)&regs[0] + 0x60;
        flags_reg.raw |= 1;
    }
    else{
        flags_reg.raw &= ~1;
    }

    uint8_t par = regs[0] & 0xff;
    par ^= par >> 4;
    par ^= par >> 2;
    par ^= par >> 1;

    flags_reg.raw |= (((~par) & 1) << 2); //Par
    flags_reg.raw |= (((regs[0]&0xff) == 0) << 6); //Zero
        flags_reg.raw |= (regs[0]&0xff) & 0b10000000;

}

void cpu_aaa(){
    --ip;

    if((regs[0] & 0xf) > 9 || (flags_reg.raw & 0x10)){

        regs[0] += 0x106;
        flags_reg.raw |= 0x10;
        flags_reg.raw |= 0x1;
    }
    else{
        flags_reg.raw &= ~(0x10);
        flags_reg.raw &= ~(0x1);
    }
    *(unsigned char*)&flags_reg.raw &= 0xf;

}


void cpu_aas(){
    --ip;

    if((regs[0] & 0xf) > 9 || (flags_reg.raw & 0x10)){

        regs[0] -= 0x06;
        --*((unsigned char*)&regs[0]+1);
        flags_reg.raw |= 0x10;
        flags_reg.raw |= 0x1;
        *(unsigned char*)&regs[0] &= 0xf;
    }
    else{
        flags_reg.raw &= ~(0x10);
        flags_reg.raw &= ~(0x1);
                *(unsigned char*)&regs[0] &= 0xf;

    }

}

void cpu_das(){

    --ip;
    uint8_t old_al = regs[0] &0xff;
    uint8_t old_cf = flags_reg.raw & 1;
    flags_reg.raw &= ~1;
    if((regs[0]&0xf) >=10 || flags_reg.raw & 0x10){
        uint16_t low = (regs[0] & 0xff) - 6;
        *(unsigned char*)&regs[0] = low&0xff;
        flags_reg.raw |= (old_cf || low & 0x1ff)?1:0;
        flags_reg.raw |= 0x10;


    }
    else{
        flags_reg.raw &= ~(0x10);
    }
    if((old_al) > 0x99 || old_cf){
        *(unsigned char*)&regs[0] -= 0x60;
        flags_reg.raw |= 1;
    }

    uint8_t par = regs[0] & 0xff;
    par ^= par >> 4;
    par ^= par >> 2;
    par ^= par >> 1;

    flags_reg.raw |= (((~par) & 1) << 2); //Par
    flags_reg.raw |= (((regs[0]&0xff) == 0) << 6); //Zero
        flags_reg.raw |= (regs[0]&0xff) & 0b10000000;
}

void cpu_cmp(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    if(opcode&1){
            set_sub_cf_of16(1,*sec,*(short*)first, 0);

        uint16_t tmp = *sec - *(short*)first;




        set_flags16(tmp);

    }
    else

    {
            set_sub_cf_of8(1,*sec,*((char*)first),0);

        uint8_t tmp = *(uint8_t*)sec - *(char*)first;


        set_flags8(tmp);

    }

    delay += 3;
}
void cpu_acmp(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode&1){
        uint16_t tmp = regs[0] - ((uint16_t)modrm | (memread(++ip + segregs[cs]*0x10) << 8));

        set_sub_cf_of16(1,regs[0], ((uint16_t)modrm | (memread(ip + segregs[cs]*0x10) << 8)),0);



        set_flags16(tmp);

    }
    else

    {
        set_sub_cf_of8(1,*((unsigned char*)&regs[0]), modrm,0);

        uint8_t tmp = *((unsigned char*)&regs[0]) - modrm;
        set_flags8(tmp);
    }
        delay += 3;

}

void cpu_inc(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    ++regs[opcode&0b111];

    char old_c = flags_reg.c;
    set_flags16(regs[opcode & 0b111]);
    flags_reg.s = !(!(regs[opcode&0b111] & 0x8000));
    flags_reg.c = old_c;



    delay += 3;
}

void cpu_dec(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    --regs[opcode&0b111];
        char old_c = flags_reg.c;

    set_flags16 (regs[opcode & 0b111]);
        flags_reg.s = !(!(regs[opcode&0b111] & 0x8000));

    flags_reg.c = old_c;



    delay += 3;
}


uint16_t stack_pop(){

    uint16_t r= memread16(regs[sp] + segregs[ss]*0x10);
        regs[sp] += 2;

    return r;
}

void cpu_push_reg(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    delay += 15;
   stack_push(regs[opcode & 0b111]);

}


void cpu_pop_reg(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    delay += 12;
        regs[opcode&0b111] =stack_pop();
}
void cpu_cond_jmp(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    char do_jmp = 0;
    char neg = !(opcode & 1);
    switch((opcode & 0xf )>> 1){
        case 0:
            do_jmp = (flags_reg.o==neg);
        break;
        case 1:
            do_jmp = (flags_reg.c==neg);
        break;
        case 2:
            do_jmp=(flags_reg.z == neg);
        break;
        case 3:
            do_jmp = (flags_reg.z | flags_reg.c) == neg;
        break;
        case 4:
            do_jmp = (flags_reg.s == neg);
        break;
        case 5:
            do_jmp = (flags_reg.p == neg);
        break;
        case 6:
            do_jmp = (flags_reg.s != flags_reg.o) == neg;
        break;
        case 7:
            do_jmp = (flags_reg.z | (flags_reg.s ^ flags_reg.o)) == neg;
        break;

    }

    delay += 4;
   if(do_jmp){
        ip += signex_8(modrm);
        delay += 15;
   }
}

void cpu_alu_imm(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    void *alu_func_table[] = {
        cpu_add, cpu_or, cpu_adc, cpu_sbb, cpu_and, cpu_sub, cpu_xor, cpu_cmp

    };

    uint8_t imm[2];
    if(opcode & 1){
        imm[0] = memread(++ip+segregs[cs]*0x10);
        if(!(opcode & 2))
            imm[1] = memread(++ip+segregs[cs]*0x10);
        else{
            imm[1] = (imm[0] & 0b10000000)?0xff:0;

        }
    }
    else{
        imm[0] = memread(++ip+segregs[cs]*0x10);
    }

        void (*alufunc)(uint16_t *,uint16_t*,uint8_t, uint8_t) = alu_func_table[(modrm >> 3) & 0b111];
        alufunc((uint16_t*)&imm,sec,modrm,opcode );
    delay += 1;
}

unsigned long long start_ticks;
bool count_cycles = false;

void cpu_xchg(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    if(first == &regs[bx]  && sec == &regs[bx]){
        count_cycles = !count_cycles;
        if(count_cycles){
            start_ticks = ticks;
        }
        else{
            printf("[IMPORTANT] CYCLE COUNT BREAKPOINT END: %lld cycles used\r\n",ticks-start_ticks);
        }
    }

   if(opcode & 1){
        if(*first != *sec){
        *first ^= *sec;
        *sec ^= *first;
        *first ^= *sec;
        }

   }else{
        uint8_t *f = (uint8_t*)first;
        uint8_t *s = (uint8_t*)sec;
        if(*s == *f) return;
        *f ^= *s;
        *s ^= *f;
        *f ^= *s;

   }
    delay += 4;

}

void cpu_mov(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    if(opcode & 1){
        *sec = *first;

    }else{

        (*(uint8_t*)sec) = (*(uint8_t*)first);

    }
    delay += 2;

}
void cpu_mov_seg(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
delay += 2;
        segregs[(modrm >> 3 )& 0b11] = *first;

}
void cpu_mov_seg_to_mem(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
delay += 2;
        *sec = segregs[(modrm >> 3) & 0b11];


}

void cpu_lea(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
        *first = effaddr;
        delay += 2;
}

void cpu_axchg(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
        --ip;

        uint16_t *secreg = &regs[(opcode)& 0b111];
       uint16_t old = *secreg;
       *secreg = regs[0];
       regs[0] = old;

       delay += 3;

}

void cpu_pop_rm(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){
    first[0] = memread(regs[sp] + segregs[ss] * 0x10);
    first[1] = memread(regs[sp] + 1 + segregs[ss] * 0x10);
    regs[sp] += 2;
}

void cpu_cbw(uint16_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){

    --ip;

   regs[0] = signex_8((char)regs[0]);
    delay += 2;
}
void cpu_stack_seg(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;

    delay += 14;
    uint16_t *reg = (uint16_t*)&segregs[opcode>>3 & 0b11];

    if(opcode & 1){
        *reg = stack_pop();
    }
    else{
        stack_push(*reg);

    }

}

void cpu_cwd(){
    --ip;
    if(regs[ax]&0x8000){
        regs[dx] = 0xffff;
    }
    else regs[dx] = 0;


}

void cpu_call_far(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){
    uint16_t new_cs, new_ip;
    uint8_t *cs_split = (uint8_t*)&new_cs;
    uint8_t *ip_split = (uint8_t*)&new_ip;

    ip_split[0] = modrm;
    ip_split[1] = memread(++ip + segregs[cs] * 0x10);

    cs_split[0] = memread(++ip + segregs[cs]*0x10);
    cs_split[1] = memread(++ip + segregs[cs] * 0x10);

    segregs[cs] = new_cs;
    ip = new_ip;

}
volatile int nodelayint;

void cpu_wait(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){
    if(opcode == 0x9b) --ip;

}

void cpu_pushf(){
    --ip;
    stack_push(flags_reg.raw);
}
void cpu_popf(){
    --ip;
    flags_reg.raw = stack_pop();
    flags_reg.r1=1;
    flags_reg.rh1=1;
    flags_reg.rh2=1;
    flags_reg.rh3=1;
    flags_reg.rh4=1;
    flags_reg.rh5=1;
}

void cpu_sahf(){
    --ip;

    uint8_t f = regs[0] >> 8;
    *(uint8_t*)&flags_reg.raw = f;
        delay +=4;


}
void cpu_lahf(){
    --ip;
    uint8_t f = flags_reg.raw&0xff;
    *(unsigned char*)(&regs[0] + 1) = f;
    delay +=4;
}



void cpu_amov(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){

        uint16_t addr = modrm & 0xff;
        addr |= ((memread(++ip + segregs[cs]* 0x10)) << 8);


        sec = (uint8_t*)&regs[0];
        first =  memgetptr(addr + segregs[((seg_override!=0)?(seg_override-1):ds)]*0x10);

        if ((opcode & 0b10)){
            uint8_t *old = first;
            first = sec;
            sec = old;
        }
        else{
            mmio_access_addr = 0;
        }


        if(opcode & 1){

            *(uint16_t *) sec = *(uint16_t *)first;
        }
        else{

            *sec = *first;
        }


                delay += 6; //shouild have approx 14 cycles of delay


}
void cpu_cmps(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    //cpu_cmp(first, sec, modrm, opcode);
    if(opcode&1){
        uint8_t src[2];
        src[0] = memread(segregs[ds] * 0x10 + regs[si]);
        src[1] = memread(segregs[ds] * 0x10 + regs[si]+1);
        uint8_t dest[2];
        dest[0] = memread(segregs[es] * 0x10 + regs[di]);
        dest[1] = memread(segregs[es] * 0x10 + regs[di]+1);
        cpu_cmp((uint16_t*)&src, (uint16_t*)&dest,modrm,opcode);
    }
    else{
        uint8_t src;
                src = memread(segregs[ds] * 0x10 + regs[si]);
                        uint8_t dest;
        dest = memread(segregs[es] * 0x10 + regs[di]);
        cpu_cmp((uint16_t*)&src,(uint16_t*) &dest,modrm,opcode);

    }

    if(flags_reg.raw & 0x400){
        regs[si] -= 1+(opcode&1);
        regs[di] -= 1+(opcode&1);
    }
    else{
        regs[si] += 1+(opcode&1);
        regs[di] += 1+(opcode&1);
    }
    delay += 14;
}
void cpu_scas(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    //cpu_cmp(first, sec, modrm, opcode);
    if(opcode&1){
        uint8_t src[2];
        src[0] = memread(segregs[ds] * 0x10 + regs[di]);
        src[1] = memread(segregs[ds] * 0x10 + regs[di]+1);

        cpu_cmp((uint16_t*)&src, &regs[0],0,opcode);
    }
    else{
        uint8_t src;
                src = memread(segregs[ds] * 0x10 + regs[di]);
        cpu_cmp((uint16_t*)&src, &regs[0],0,opcode);
    }
    if(flags_reg.raw & 0x400){
        regs[di] -= 1+(opcode&1);
    }
    else{
        regs[di] += 1+(opcode&1);
    }
    delay += 11;
}

void cpu_movs(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    if(opcode&1){
        uint8_t src[2];
        *(uint16_t*)&src = memread16(segregs[ds] * 0x10 + regs[si]);

        memwrite(src[0], segregs[es] * 0x10 + regs[di]);
        memwrite(src[1], 1+segregs[es] * 0x10 + regs[di]);

    }
    else{
        uint8_t src;
                src = memread(segregs[ds] * 0x10 + regs[si]);
        memwrite(src, segregs[es] * 0x10 + regs[di]);

    }

    if(flags_reg.d){
        regs[si] -= 1+(opcode&1);
        regs[di] -= 1+(opcode&1);
    }
    else{
        regs[si] += 1+(opcode&1);
        regs[di] += 1+(opcode&1);


    }
    delay += 10;


}

void cpu_lods(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;

    if(opcode&1){
        uint8_t src[2];
        src[0] = memread(segregs[((seg_override!=0)?(seg_override-1):ds)] * 0x10 + regs[si]);
        src[1] = memread(segregs[((seg_override!=0)?(seg_override-1):ds)] * 0x10 + regs[si]+1);

        regs[0] = *(uint16_t*)src;
    }
    else{
        uint8_t src;
            src = memread(segregs[((seg_override!=0)?(seg_override-1):ds)] * 0x10 + regs[si]);

        *((uint8_t*)&regs[0]) = src;
    }

    if(flags_reg.raw & 0x400){
        regs[si] -= 1+(opcode&1);
    }
    else{
        regs[si] += 1+(opcode&1);
    }
    delay += 8; //4+4+8=16


}
void cpu_stos(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;


    if(opcode&1){
        uint8_t src[2];
        *(uint16_t*)src = regs[0];

        memwrite(src[0], segregs[es] * 0x10 + regs[di]);
        memwrite(src[1], 1+segregs[es] * 0x10 + regs[di]);

    }
    else{
        uint8_t src;
                src =regs[0] &0xff;
        memwrite(src, segregs[es] * 0x10 + regs[di]);
    }

    if(flags_reg.raw & 0x400){
        regs[di] -= 1+(opcode&1);
    }
    else{
        regs[di] += 1+(opcode&1);
    }

    delay += 8;

}

void cpu_reg_mov8(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){

    if(opcode & 0b100){
        *((uint8_t*)&regs[opcode&0b11]+1) = modrm;
    }
    else{
        *(uint8_t*)&regs[opcode&0b11] = modrm;

    }

}

void cpu_reg_mov(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){
    uint16_t src = modrm;
    src |= (memread(++ip+segregs[cs]*0x10) << 8);

    regs[(opcode & 0b111) ] = src;

}
void cpu_ret_imm(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

        uint16_t val = memread(regs[sp] + segregs[ss]*0x10) | (memread(regs[sp]+1 + segregs[ss]*0x10) << 8);
        ip = val;

        regs[sp] += 2;

        uint16_t off = modrm | (memread(++ip + segregs[cs]*0x10) << 10);

        regs[sp] += off;


}
void cpu_retf_imm(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

        uint16_t val = memread(regs[sp] + segregs[ss]*0x10) | (memread(regs[sp]+1 + segregs[ss]*0x10) << 8);
        ip = val;

        regs[sp] += 2;

        uint16_t new_cs = memread(regs[sp] + segregs[ss]*0x10) | (memread(regs[sp]+1 + segregs[ss]*0x10) << 8);
        segregs[cs] = new_cs;

        regs[sp] += 2;

        uint16_t off = modrm | (memread(++ip + segregs[cs]*0x10) << 10);

        regs[sp] += off;


}
void cpu_ret(){
    --ip;
        uint16_t val = memread(regs[sp] + segregs[ss]*0x10) | (memread(regs[sp]+1 + segregs[ss]*0x10) << 8);
        ip = val;

        regs[sp] += 2;


}
void cpu_retf(){
    --ip;
        uint16_t val = memread(regs[sp] + segregs[ss]*0x10) | (memread(regs[sp]+1 + segregs[ss]*0x10) << 8);
        ip = val;

        regs[sp] += 2;
        uint16_t new_cs = memread(regs[sp] + segregs[ss]*0x10) | (memread(regs[sp]+1 + segregs[ss]*0x10) << 8);
        segregs[cs] = new_cs;

        regs[sp] += 2;

}
void cpu_les(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    *first  = *sec;
    segregs[es] = sec[1];

    }
void cpu_lds(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    *first  = *sec;
    segregs[ds] = sec[1];
}

void cpu_mov_imm(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    if(opcode & 1){
        uint8_t imm[2];
        imm[0] = memread(++ip + segregs[cs]*0x10);
        imm[1] = memread(++ip + segregs[cs]*0x10);
        *sec = *((uint16_t*)&imm[0]);
        delay -= 4;
    }
    else{

        uint8_t imm = memread(++ip + segregs[cs]*0x10);
        *(uint8_t*)sec = imm;
    }

     //override delay to 4

}
void start_int(uint16_t vec){

    stack_push(flags_reg.raw);
    flags_reg.raw &= ~(0x200 | 0x100 | 0x10);

    stack_push(segregs[cs]);
    stack_push(ip-1);

    segregs[cs] = memread16(vec * 4+2);
    ip = memread16(vec*4);
    //--ip;

    delay += 12;
    enable_rep = 0;


}

pthread_mutex_t intsync;
uint8_t inta = 1;

void cpu_hw_start_int (uint8_t vec){
    if(!flags_reg.i){
       // printf("INT %x dropped\n", vec);
        return;
    }
            inta = 0;

    while(!dbgsync){
            inta = 0;

    }

	while(nodelayint&&delay ){

	}

    while(pthread_mutex_trylock(&intsync)){
        inta = 0;
    }



    if(flags_reg.i ){
		if(enable_rep){
				--ip;
		}

        start_int(vec);

    }
    inta = 1;


    pthread_mutex_unlock(&intsync);

}

void cpu_int3(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    start_int(3);

}

void cpu_int0(){
    --ip;
    if(flags_reg.o){
        start_int(4);
    }

}

void cpu_int(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    ++ip;
    start_int(modrm);
    --ip;

}

void cpu_aam(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    uint8_t tmp =     ((uint8_t*) &regs[0])[0];

    ((uint8_t*) &regs[0])[1] = tmp / modrm;
    ((uint8_t*) &regs[0])[0] = tmp % modrm;
    set_flags8(regs[0] & 0xff);

}

void cpu_aad(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){

    uint8_t tmp =     ((uint8_t*) &regs[0])[0];
    uint8_t tmph = ((uint8_t*) &regs[0])[1];

    ((uint8_t*) &regs[0])[0] = (tmp + (tmph * modrm)) & 0xff;
    ((uint8_t*) &regs[0])[1] = 0;
    set_flags8(regs[0] & 0xff);

}

void cpu_iret(){

    ip = stack_pop();
    segregs[cs] = stack_pop();
    flags_reg.raw = stack_pop();


}

void shift_rot1(uint8_t cNdir, uint8_t sz, uint16_t *in){

    if(cNdir & 1) { //direction = right (RCR)

        unsigned char lsb = *in & 1; //save lsb for rot
        if(sz){ //large size
            *in >>= 1;
        }
        else{
            *((uint8_t*)in) >>= 1; //8 bit shift

        }


        uint16_t top_bit = !!((cNdir & 0b10 /*with carry?*/)?flags_reg.c:lsb);

        flags_reg.c = lsb; //set it for c flag

        top_bit <<= (sz?15:7); //either shift by 7 or 15
        *in |= top_bit; //or it
        if(sz)
            flags_reg.o = (!!(*in&0x8000))^(!!(*in&0x4000));
        else
            flags_reg.o = (!!(*in&0x80))^(!!(*in&0x40));
    }
    else{
        unsigned char msb;
        if(sz){
            msb = !!(*in & 0x8000); //save msb for rot(16)
            *in <<= 1; // 16 bit shift
        }
        else{
            msb = !!(*in & 0x80); //save msb for rot
            *(uint8_t*) in <<= 1; //8 bit shift
        }

        uint8_t bottom_bit = (cNdir&0b10)?flags_reg.c:msb;
        flags_reg.c = msb; //set it anyway
        *in |= bottom_bit;

    }

}
void shift_sh1(uint8_t cNdir, uint8_t sz, uint16_t *in){
    if(cNdir & 1){

        flags_reg.c = *in & 0x1;
        if(cNdir & 0b10){
            if(sz){
                *in >>= 1; //sar
                if(*in&0x4000){
                    *in|=0x8000;
                }
            }
            else{
                    (*(char*)in) >>= 1;
                if(*(char*)in&0x40){
                    *(char*)in|=0x80;
                }
            }
        }
        else
        {
            if(sz){
                *(unsigned short*) in >>= 1;//shr
            }
            else{
                *(unsigned char *)in >>= 1;
            }
        };
    }
    else{
        if(sz){
            flags_reg.c = !!(*in & 0x8000);
            *in <<= 1;
        }
        else{
            flags_reg.c = !!(*in & 0x80);
            *(unsigned char*)in <<= 1;
        }
    }


}
void cpu_shifter(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    delay += 2;
    switch((modrm>>3) & 0b111){
        case 0:
        case 1:
        case 2:
        case 3:
            if(opcode & 0b10){
                        delay += 4;

                for(int i=0; i < (regs[cx] & 0x1f) ;++i){
                    shift_rot1((modrm>>3) & 0b11, opcode & 1, sec);
                    delay += 4;
                }
            }
            else{
                shift_rot1((modrm>>3) & 0b11,opcode & 1, sec);
            }
        break;

        case 4:
        case 5:
        case 6:
        case 7:
           if(opcode & 0b10){
                        delay += 4;

                for(int i=0; i < (regs[cx]&0x1f);++i){
                    shift_sh1(((modrm >>3)& 0b11), opcode & 1, sec);
                    delay += 4;

                }

                if((regs[cx] & 0xff) > 0x1f){
                    switch(modrm & 0b11){

                        case 4:
                        case 6:
                            flags_reg.o = ((*sec & 0x8000) >> 15) ^ flags_reg.c; //sal flags
                            break;
                        case 7:
                            flags_reg.o = 0; //sar flags
                            break;
                        case 5:
                            flags_reg.o = ((*sec & 0x8000) >> 15); //shr flags


                    }

                }
                if(regs[cx] & 0xff){
                    if(opcode & 1)
                        set_flags16(*sec);
                    else set_flags8(*sec);

                }
            }
            else{
                shift_sh1((modrm >>3)& 0b11,opcode & 1, sec);
                           if(opcode & 1)
                        set_flags16(*sec);
                    else set_flags8(*sec);
            }


             break;

    }
    delay += 2;
}

void cpu_salc(){
    --ip;
    *(unsigned char*)&regs[0] = flags_reg.c * 0xff;

}
void cpu_xlat(){
    --ip;
    *(unsigned char*)&regs[0] = memread(segregs[((seg_override!=0)?(seg_override-1):ds)] * 0x10 + regs[bx] + *(uint8_t*)&regs[0]);
    delay += 7; //7+4=11
}

void cpu_loop(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    uint16_t yesbranch=1;

    --regs[cx];
    switch((opcode & 0b11)){
        case 0:
        case 1:
        yesbranch = ((opcode &1) == flags_reg.z);
        break;
        default: yesbranch = 1; break;

    }

    if((yesbranch==0) || regs[cx] == 0){
    delay += 5;
        return;
    }
    delay += 17;
    ip += signex_8(modrm);

}

void cpu_jcxz(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    if(regs[cx] == 0) ip += (char) modrm;

}

void cpu_lock(){
--ip;
}



int in_hlt = 0;

void cpu_hlt(){
   // inta = 1;
    --ip;

    dbgsync = 1;
    in_hlt=1;
    if(flags_reg.i == 0) { printf("WARNING: HLT BUT NO INTS\n");}

    while(inta){
        struct timespec ts = {0, 100000};
        nanosleep(&ts, NULL);
    }

    in_hlt = 0;
    dbgsync = 0;
   // inta = 1;
}

void cpu_cmc(){
    --ip;
    flags_reg.c = !flags_reg.c;

}

void cpu_not(uint16_t *first, uint16_t* sec, uint8_t modrm, uint8_t opcode){
    if(opcode & 1){
        *sec = ~*sec;
    }
    else{
        *(uint8_t*)sec = ~*(uint8_t *)sec;
    }

}

void cpu_neg(uint16_t *first, uint16_t* sec, uint8_t modrm, uint8_t opcode){
    flags_reg.c = !!(*sec != 0);
    uint16_t zero = 0;
    if(opcode & 1){
        *sec = -*sec;
        set_flags16(*sec);
            set_sub_cf_of16(0,zero, *sec,0);

    }
    else{
        *(uint8_t*)sec =  -*(uint8_t *)sec;
        set_flags8(*sec);
                set_sub_cf_of8(0,zero, *sec,0);

    }

}

void cpu_mul(uint16_t *first, uint16_t* sec, uint8_t modrm, uint8_t opcode){
    if(opcode & 1){
        uint32_t o = *sec * regs[0];
        regs[ax] = o & 0xffff;
        regs[dx] = o >> 16 & 0xffff;
        flags_reg.o = flags_reg.c = (regs[dx] != 0);
        delay += 125;
    }
    else{
        regs[0] = *((uint8_t*)sec) * (uint8_t)(regs[0] & 0xff);
        flags_reg.o = flags_reg.c = ((regs[0] >> 8) != 0);
        delay += 70;
    }

}
void cpu_div(uint16_t *first, uint16_t* sec, uint8_t modrm, uint8_t opcode){

    if(opcode & 1){
        uint32_t da = (regs[dx] << 16) | regs[ax];
        if(*sec == 0){
            start_int(0);
            return;
        }

        uint32_t o = da / *sec;
        regs[ax] = o & 0xffff;
        regs[dx] = (da % *sec) & 0xffff ;
        delay += 150;
    }
    else{
        uint16_t a = regs[ax];
        if((*sec &0xff)== 0){
            start_int(0);
            return;
        }
        ((unsigned char*)&regs[ax])[0] = a/(*sec & 0xff);
        ((unsigned char*)&regs[ax])[1]  = a%(*sec & 0xff);
        delay += 85;
    }

}
void cpu_idiv(uint16_t *first, uint16_t* sec, uint8_t modrm, uint8_t opcode){
    if(opcode & 1){
        if(*sec == 0){
            start_int(0);
            return;
        }

        uint32_t da = (regs[dx] << 16) | regs[ax];
        int o = (int)da / *((short*)sec);
        regs[ax] = o & 0xffff;
        regs[dx] = ((int)da % *(short*)sec) & 0xffff ;
        delay += 165;
    }
    else{
        if((*sec &0xff)== 0){
            start_int(0);
            return;
        }
        short a = (short)regs[ax];
        char b = *((char*)sec);
        *((unsigned char*)&regs[ax]) = a/b;
        *((unsigned char*)&regs[ax]+1) = a%b;
        delay += 110;
    }


}
void cpu_imul(uint16_t *first, uint16_t* sec, uint8_t modrm, uint8_t opcode){
    if(opcode & 1){
        uint32_t o = (short)*sec * (short)regs[0];
        regs[ax] = o & 0xffff;
        regs[dx] = o >> 16 & 0xffff;
        flags_reg.o = flags_reg.c = (regs[dx] != 0);
        delay += 154;
    }
    else{
        regs[0] = *(char*)sec * (char)(regs[0] & 0xff);
        flags_reg.o = flags_reg.c = ((regs[0] >> 4 & 0xf) != 0);
        delay += 95;
    }

}
void cpu_mlu(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    void *cpu_mlu_func_tab []={
        cpu_test, cpu_test,cpu_not, cpu_neg, cpu_mul, cpu_imul, cpu_div, cpu_idiv

    };
    void (*mfunc)(uint16_t *,uint16_t*,uint8_t, uint8_t) = cpu_mlu_func_tab[(modrm >> 3) & 0b111];

    uint8_t imm[2];
    if((modrm >> 3 & 0b111 )<= 1){
    if(opcode & 1){
        imm[0] = memread(++ip+segregs[cs]*0x10);
        if((opcode & 2))
            imm[1] = memread(++ip+segregs[cs]*0x10);
        else{
            imm[1] = (imm[0] & 0b10000000)?0xff:0;

        }

    }
    else{
        imm[0] = memread(++ip+segregs[cs]*0x10);
    }
    }
    mfunc((uint16_t*)imm,sec,modrm,opcode);

}
void cpu_cf(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    flags_reg.c = (opcode & 1);
}
void cpu_if(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    flags_reg.i = (opcode & 1);
    if(flags_reg.i) mmuen = 1;


}
void cpu_df(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    --ip;
    flags_reg.d = (opcode & 1);
}

void cpu_misc_fe(uint8_t *first, uint8_t *sec, uint8_t modrm, uint8_t opcode){

    if((modrm >> 3 )& 0b1){
        --*sec;
    }
    else{
        ++*sec;
    }

    set_flags8(*sec);
    flags_reg.s = !(!(*sec & 0x80));

    delay += 27;
}
void cpu_misc_ff(uint16_t *first, uint16_t *sec, uint8_t modrm, uint8_t opcode){
    switch((modrm >> 3) &0b111){
        case 0: //INC
        case 1:
            if((modrm >> 3 )& 0b1){
            --*sec;
        }
        else{
            ++*sec;
        }
        delay += 26;
        set_flags16(*sec);
            flags_reg.s = !(!(*sec & 0x8000));
        break;

        case 2: //CALL
            stack_push(ip);
            ip = *sec-1;
            delay += 32;
        break;
        case 3:
            {
            stack_push(segregs[cs]);
            ++ip;
            uint16_t seg = memread16(ip + segregs[cs] * 0x10);
            ++ip;
            ++ip;
            uint16_t newip = memread16(ip + segregs[cs] * 0x10);
            ++ip;
            stack_push(ip);
            ip = newip-1;
            segregs[cs] = seg;
            delay += 57;
            }
        break;
        case 4: //JMP
            ip = *sec-1;
            delay += 21;


        break;
        case 5:
            {
            uint32_t jaddr = ((uint32_t)memread16((uint32_t)ip + segregs[cs] * 0x10-1)) + (segregs[(((seg_override!=0)?(seg_override-1):ds))])*0x10;
            jaddr &= 0xfffff;
            segregs[cs] = memread16(jaddr+2);
            ip = memread16(jaddr) -1;
            delay += 28;


            }
        break;

    }

}
void *opcode_func_table[256]={
    cpu_add,cpu_add,cpu_add,cpu_add, cpu_aadd, cpu_aadd, cpu_stack_seg, cpu_stack_seg, cpu_or,cpu_or,cpu_or,cpu_or,cpu_aor,cpu_aor, cpu_stack_seg, cpu_stack_seg,
    cpu_adc,cpu_adc,cpu_adc,cpu_adc,cpu_aadc, cpu_aadc, cpu_stack_seg, cpu_stack_seg,cpu_sbb,cpu_sbb,cpu_sbb,cpu_sbb,cpu_asbb,cpu_asbb, cpu_stack_seg, cpu_stack_seg,
    cpu_and,cpu_and,cpu_and,cpu_and,cpu_aand,cpu_aand, cpu_seg_override, cpu_daa,cpu_sub,cpu_sub,cpu_sub,cpu_sub,cpu_asub,cpu_asub, cpu_seg_override, cpu_das,
    cpu_xor,cpu_xor,cpu_xor,cpu_xor,cpu_axor,cpu_axor,cpu_seg_override,cpu_aaa,cpu_cmp,cpu_cmp,cpu_cmp,cpu_cmp,cpu_acmp,cpu_acmp,cpu_seg_override, cpu_aas,
    cpu_inc,cpu_inc,cpu_inc,cpu_inc,cpu_inc,cpu_inc,cpu_inc,cpu_inc,cpu_dec,cpu_dec,cpu_dec,cpu_dec,cpu_dec,cpu_dec,cpu_dec,cpu_dec
    ,cpu_push_reg,cpu_push_reg,cpu_push_reg,cpu_push_reg,cpu_push_reg,cpu_push_reg,cpu_push_reg,cpu_push_reg,cpu_pop_reg,cpu_pop_reg,cpu_pop_reg,cpu_pop_reg,cpu_pop_reg,cpu_pop_reg,cpu_pop_reg,cpu_pop_reg,

    cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp, cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,
    cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp, cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,cpu_cond_jmp,

    cpu_alu_imm,cpu_alu_imm,cpu_alu_imm,cpu_alu_imm, cpu_test, cpu_test, cpu_xchg,cpu_xchg, cpu_mov,cpu_mov,cpu_mov,cpu_mov, cpu_mov_seg_to_mem, cpu_lea, cpu_mov_seg, cpu_pop_rm,

    cpu_axchg, cpu_axchg, cpu_axchg, cpu_axchg, cpu_axchg, cpu_axchg, cpu_axchg, cpu_axchg, cpu_cbw,cpu_cwd,cpu_call_far,cpu_wait,cpu_pushf, cpu_popf,cpu_sahf, cpu_lahf
    ,cpu_amov,cpu_amov,cpu_amov,cpu_amov, cpu_movs, cpu_movs,cpu_cmps, cpu_cmps,cpu_atest,cpu_atest,cpu_stos, cpu_stos, cpu_lods, cpu_lods,cpu_scas,cpu_scas
    ,
    cpu_reg_mov8, cpu_reg_mov8,cpu_reg_mov8,cpu_reg_mov8,    cpu_reg_mov8, cpu_reg_mov8,cpu_reg_mov8,cpu_reg_mov8,cpu_reg_mov,  cpu_reg_mov,  cpu_reg_mov,  cpu_reg_mov,  cpu_reg_mov,  cpu_reg_mov,  cpu_reg_mov,  cpu_reg_mov,
    cpu_ret_imm, cpu_ret,cpu_ret_imm,cpu_ret,cpu_les,cpu_lds,cpu_mov_imm,cpu_mov_imm,cpu_retf_imm, cpu_retf,cpu_retf_imm,cpu_retf,cpu_int3,cpu_int,cpu_int0,cpu_iret,
    cpu_shifter, cpu_shifter, cpu_shifter,cpu_shifter,cpu_aam, cpu_aad,
    cpu_salc, cpu_xlat,
    cpu_wait, cpu_wait, cpu_wait, cpu_wait, cpu_wait, cpu_wait, cpu_wait, cpu_wait,
    cpu_loop,cpu_loop,cpu_loop,cpu_jcxz,
    cpu_wait, cpu_wait, cpu_wait, cpu_wait,cpu_call16, cpu_jmp16, cpu_farjmp, cpu_jmp8 //cpu io instructions,
    ,cpu_wait,cpu_wait,cpu_wait,cpu_wait//more io stuff,

    ,cpu_lock,cpu_lock, cpu_rep,cpu_rep,
    cpu_hlt, cpu_cmc,
    cpu_mlu, cpu_mlu,
    cpu_cf, cpu_cf,
    cpu_if, cpu_if,
    cpu_df,cpu_df,
    cpu_misc_fe, cpu_misc_ff,




};


unsigned char test[] = {
  0x01, 0xd8, 0x00, 0xda,0xe9,0xfd,0xff,0,0,0,0,0,0,0,0,0
};



uint16_t *get_reg(uint8_t code,uint8_t iswide){
        uint8_t *ret = (uint8_t*)&regs[code];

        if((iswide == 0)&& code >= 0b100 ){
            ret = (uint8_t*)&regs[code& 0b11];
            *((unsigned long*)&ret) += 1;
        }

    return (uint16_t*)ret;
}



uint64_t ips = 0;
char * nametable[]={
"ax","cx","dx","bx", "sp","bp","si","di"
};
char * segtable[]={
"es","cs","ss","ds"

};
char * flagstable[]={
    "C", "R", "P", "R", "A", "R", "Z", "S", "T", "I", "D","O","R","R","R","R"

};
            char regstr[999];

char* cpu_dump_debug(){
            while(!dbgsync);

            sprintf(regstr, "AX=%04x BX=%04x CX=%04x DX=%04x SP=%04x BP=%04x SI=%04x, DI=%04x CS=%04x DS=%04x ES=%04x SS=%04x IP=%04x IPDUMP=%02x %02x %02x", regs[ax], regs[bx], regs[cx], regs[dx],
            regs[sp], regs[bp], regs[si], regs[di],
            segregs[cs], segregs[ds], segregs[es], segregs[ss],
            ip, memread(segregs[cs]*0x10+ip),memread(segregs[cs]*0x10+ip+1),memread(segregs[cs]*0x10+ip+2));

            return regstr;

}

char* cpu_dump_flags_debug(){
            while(!dbgsync);

            memset(regstr, 0, 999);

            strcat(regstr, "FLAGS=");
            for(int i=0; i<16; ++i){
                if(flags_reg.raw & (1 << i)){
                    strcat(regstr, flagstable[i]);
                }
                else{
                    strcat(regstr, "_");
                }
            }

            return regstr;

}
int cpu_do_reset = 0;

void cpu_reset(){
    cpu_do_reset=1;
}

void get_rm_arg(uint16_t **sec, uint8_t modrm, uint8_t opcode, uint16_t seg){
        uint16_t *second;
            uint32_t off=0;
        uint32_t seg_off=0;
        seg = (seg_override!=0)?seg_override-1:ds;


        if((modrm >> 6) != reg){
            uint8_t rm = modrm & 0b111;
             switch(rm){
                case 0:
                    off = regs[bx] + regs[si];
                    seg_off= segregs[seg]*0x10;
                    delay += 12;
                    break;
                case 1:
                    off = regs[bx] + regs[di];
                                        seg_off= segregs[seg]*0x10;

                    delay += 12;
                    break;
                case 2:
                    off = regs[bp] + regs[si] ;
                                        seg_off= segregs[ss]*0x10;
                    delay += 8;
                    break;
                case 3:
                    off = regs[bp] + regs[di];
                                                            seg_off= segregs[ss]*0x10;

                    delay += 7;
                    break;
                case 4:
                    off =regs[si] ;
                                                            seg_off= segregs[seg]*0x10;

                    delay +=5;
                   break;
                case 5:

                    off = regs[di];
                                                            seg_off= segregs[seg]*0x10;
                    delay += 5;
                    break;
                case 6:
                    off = regs[bp];
                                                            seg_off= segregs[ss]*0x10;

                    delay += 5;
                    break;
                case 7:
                    delay += 5;
                    off = regs[bx];
                                                            seg_off= segregs[seg]*0x10;

                    break;
                break;

             }
        }


        switch(modrm>>6){
            case regptr:
                {

                    if((modrm & 0b111 )== 0b110){

                        uint16_t addr = memread16(++ip + segregs[cs] *0x10);
                        second = (uint16_t*)memgetptr(addr + segregs[seg]*0x10);
                        ++ip;
                        delay -= 4;

                    }
                    else{
                        off += seg_off;

                        second = (uint16_t*)memgetptr(off );
                        delay -= 4;
                    }
                    delay +=  2;
                }
            break;
            case offset8:

                off += (short)(char)memread(++ip + segregs[cs]*0x10);
                off += seg_off;

                second = (uint16_t*)memgetptr(off );
                delay -= 3;
            break;
            case offset16:
                *(short*)&off += (short)memread16(++ip + segregs[cs]*0x10);
                        off += seg_off;

                second = (uint16_t*)memgetptr(off);
                delay -= 7;

                ++ ip;
            break;
            case reg:
                {
                second = get_reg(modrm & 0b111,(opcode & 1) || (opcode == 0xc4 || opcode == 0xc5));

                }
            break;

        }


        effaddr = off ;
        *sec = second;
        ++delay;

}

void cpu_step()
 {

        if(!delay ){
        dbgsync = 0;
        ++ips;

        uint8_t opcode = memread(ip + segregs[cs]*0x10);



        void (*opfunc)(uint16_t *,uint16_t*,uint8_t, uint8_t) = opcode_func_table[opcode];

        if(opfunc == 0){
                    dbgsync = 1;

            printf("UNIMPLEMENTED INSTRUCTION %x AT CSIP%x %x\n", opcode, segregs[cs], ip);
            exit(0);
        }
        uint16_t *first, *second;
                mmio_buf = 0;
        mmio_access_addr = 0;


        uint8_t modrm = memread(++ip + segregs[cs]*0x10);
        delay -= 4; //override
        uint8_t instr_reg = (modrm  >> 3 ) & 0b111;

        second = first = 0;


        first = get_reg(instr_reg, (opcode & 1)  |  (opcode >= 0x8c && opcode <= 0x8f) | (opcode == 0xc4 || opcode == 0xc5));

        uint16_t seg = ds + 1;

        if(seg_override) seg = seg_override;


        if((!(opcode & 0b100) && opcode < 0x40) || (opcode == 0xf6 || opcode == 0xf7 ||opcode == 0xfe || opcode == 0xff)|| ((opcode == 0xc6) || (opcode == 0xc7))|| (((opcode >> 4) & 0xf) == 0x8) || (opcode == 0xc4 || opcode == 0xc5) || (((opcode >> 4 & 0xf)==0xd)
        && ((opcode & 0xf) <=0x3)) || ((((opcode >> 4) & 0xf) == 0xf) &&( (opcode == 0xf6) || (opcode == 0xf7 ) || (opcode >= 0xfe)))){
            get_rm_arg(&second, modrm,opcode | (opcode >= 0x8c && opcode <= 0x8f), seg);

            if( ((opcode & 0b10)&& (opcode < 0x40))||((((opcode >> 4) & 0xf) == 0x8)&& ((opcode & 0b1111) >=4) && (opcode & 0b10))){
                if(first != second){
                    uint16_t *old = first;
                    first = second;
                    second = old;
                }
            }

        }
        		nodelayint = 0;

        if(opfunc){
            opfunc(first,second,modrm,opcode );
        }



        int mask = 0b1111000000101010;
        if((flags_reg.raw & mask) != mask){
          //  printf("WARNING: Attempting to set reserved flags to zero at CS:IP %04x:%04x, opcode = %02x\n", segregs[cs], ip,opcode2);
            flags_reg.raw |= mask;
        }

        dbgsync=1;


        if(opfunc != cpu_seg_override){

                seg_override = 0;

        }

        if(mmio_access_addr != 0){
            memwrite(mmio_buf,mmio_access_addr);
            delay -= 4;
        }



        if(enable_rep){

            --regs[cx];
            if(opcode == 0xf3 || opcode == 0xf2){ //fix cx early decrement
                ++regs[cx];
            }

            if(regs[cx] && (!(opcode == 0xAE || opcode == 0xAF || opcode == 0xa6 || opcode == 0xa7)|| (!!(enable_rep - 1) == flags_reg.z))  ){

            }
            else{
                ++ip;
                enable_rep = 0;
            }
            delay -= (4+1); //one cycle for increment and check, less 4 cycles bonus because no fetch

        }
        else{

                        ++ip;

        }




            if(delay && delay >0) --delay;
                pthread_mutex_unlock(&intsync);

            if(segfault && mmuen){
                mmuen = 0;
                segfault = 0;
                start_int(2); //NMI
            }
        if(flags_reg.raw & 0x100){
            start_int(1);
        }
                pthread_mutex_lock(&intsync);


        }


        if(delay) --delay;

                ++ticks;



    };
#include <execinfo.h>
struct sigaction oldSA;
static void catch_segv(int sig, siginfo_t *info){
    printf("UNAUTHORISED ACCESS!!! cs:ip=%x:%x, si_addr=%x\n\r",segregs[cs], ip, info->si_addr);
    if(info->si_addr > rom && info->si_addr <= &rom[131071]){
        printf("TRYING TO WRITE TO ROM AT 0x%x\r\n", 0xe0000+ (unsigned long)info->si_addr - (unsigned long)rom);
    }
    void *array[10];
    size_t size=10;
      // print out all the frames to stderr
  fprintf(stderr, "Error: signal %d:\n", sig);
  //backtrace_symbols_fd(array, size, STDERR_FILENO);

    sigaction(SIGSEGV, &oldSA, NULL);
}

extern char *aqxe_name;

void cpu_init(){
    ip = 0x0;
    segregs[cs] = 0xffff;
    segregs[ds] = 0;
    segregs[es] = 0;
    segregs[ss] = 0;

    delay += 0;
    mmuen = 0;
    flags_reg.raw = 0;
    flags_reg.r1 = 1;
    flags_reg.r=1;
    flags_reg.rh1 = 1;
    flags_reg.rh2 = 1;
    flags_reg.rh3=1;
    flags_reg.rh4=1;
    flags_reg.rh5=1;

    enable_rep = 0;

    memset(regs, 0, sizeof(uint16_t)*8);

    if(aqxe_name){
        printf("Attempting to load aqxe program %s\r\n",aqxe_name);
        //load from aqxe if one was specified

        FILE *aqxe_file = fopen(aqxe_name, "rb");
        if(!aqxe_file){
            perror("fopen");
            exit(-1);
        }

        short cmd;

        int ret;
        while((ret = fread(&cmd, 2, 1, aqxe_file)) > 0){
        switch(cmd){
            case 0x4753: //'SG', load segment
                unsigned short sz;
                unsigned short addr;
                unsigned short seg;
                fread(&sz,2,1,aqxe_file);
                fread(&addr,2,1,aqxe_file);
                fread(&seg,2,1,aqxe_file);


                printf ("Loading a %d byte segment at %x:%x\r\n", sz, seg, addr+8);

                unsigned char *buf = malloc(sz); //read buffer
                int readed = 0;
                while(readed < sz){
                    readed += fread(buf, 1, sz-readed, aqxe_file);
                }
                unsigned int org = seg*0x10 + addr + 8;

                for(int i=0; i<sz;++i){
                    memwrite(buf[i], org+i);
                }
                free(buf);
            break;
            case 0x4e52: //RN, run
                fread(&addr,2,1,aqxe_file);
                fread(&seg,2,1,aqxe_file);
                ip = addr;
                segregs[cs] = seg;
                printf("Setting CS:IP to program entry point %x:%x\r\n", segregs[cs],ip);
                goto exit; //im sorry
            break;
            default:
                printf("Unknown command %.2s\r\n",( char*)&cmd);
                goto exit;
        }
        }

        exit:;
        printf("Successfully loaded %s\r\n", aqxe_name);

    }

}

#define CPU_FREQ 6293750
#define BATCH_TICKS 10000

void *system_func(){


    memory = malloc(131072*3); //3 banks of ram
   // rom = malloc(131072);
   for(int i=0;i<131072*3;++i){
        memory[i] = rand();
   }



    cpu_do_reset = 1;

    int romf = open("rom.bin", O_RDONLY,0);
    if(!romf) {
        printf("%s\n", "CANNOT OPEN rom.bin");
        exit(1);
    }

    rom = mmap(NULL, 131072, PROT_READ, MAP_PRIVATE | MAP_POPULATE,romf,0);

    if(*((unsigned short*)&(rom[0x20000-6])) == 0xcafe && aqxe_name){ //using a serial bootloader
        printf("Serial BIOS rom detected, installing disp handler\n");
        memcpy(&memory[255*4],&rom[0x20000-4], 4); //copy int 255 addr
    }

    struct sigaction sa;
    sa.sa_flags = SA_SIGINFO;
    sa.sa_handler = (__sighandler_t)catch_segv;
    if(sigaction(SIGSEGV, &sa, &oldSA) == -1){
        printf("setting segv handler failed, %s\n", strerror(errno));

    }

    usleep(6000);

    long batch_target_ns = (long)((double)BATCH_TICKS * 1000000000.0 / CPU_FREQ);
    struct timespec next_wake;
    clock_gettime(CLOCK_MONOTONIC, &next_wake);

    char key_pop_buf();
    while(1){
        for(long i = 0; i < BATCH_TICKS; ++i) {
            if(cpu_do_reset){
                cpu_init();
                cpu_do_reset = 0;
            }
            cpu_step();
        }

        next_wake.tv_nsec += batch_target_ns;
        if(next_wake.tv_nsec >= 1000000000L) {
            next_wake.tv_sec++;
            next_wake.tv_nsec -= 1000000000L;
        }
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next_wake, NULL);
    }

    return NULL;

}
