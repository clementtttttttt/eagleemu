#include <stdint.h>
void gfx_write_fifo(unsigned char in);
void gfx_reset_ptr();
uint8_t* gfx_get_addr(uint16_t addr);
void gfx_clear();
void gfx_init_vram();
