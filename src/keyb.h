#include <stdbool.h>
#define MAX_PS2_CODE_LEN 8
int ps2_encode(int sdl_scancode, bool pressed) ;
uint16_t* keyb_get_shiftreg();
void key_set_buf(uint8_t c);
char key_pop_buf();
