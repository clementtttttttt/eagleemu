#include "8255.h"

static uint8_t regs[] = {
    /*PORTA*/0, /*PORTB*/ 0, /*PORTC*/ 0, /*CTRL*/0x9b

};
uint8_t *i8255_get_reg(uint8_t addr){

    return &regs[addr];
}
