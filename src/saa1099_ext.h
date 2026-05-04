
void saa1099_ext_init();
uint8_t *saa1099_get_addr();
void saa1099_ext_write_data(uint8_t in);
void saa1099_ext_tick(void *userdata, uint8_t *stream, int len);
