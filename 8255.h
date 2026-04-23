#include <stdint.h>
uint8_t *i8255_get_reg(uint8_t addr);
struct i8255_ctrl{
    uint8_t PCLI : 1;
    uint8_t PBLI : 1;
    uint8_t M1SEL : 1;
    uint8_t PCUI : 1;
    uint8_t PAUI : 1;
    uint8_t M2SEL : 2;
    uint8_t MSET : 1;
};
