
#include <SAASound.h>
#include <stdint.h>
#include <stdlib.h>

static SAASND saahandle;

static uint8_t curr_addr;


void saa1099_ext_init(){

    saahandle = newSAASND();

    SAASNDClear(saahandle);

    SAASNDSetSampleRate(saahandle, 44100);
    SAASNDSetClockRate(saahandle, 6293750);
}

uint8_t *saa1099_get_addr(){
   return  &curr_addr;
}
void saa1099_ext_write_data(uint8_t in){
    SAASNDWriteAddressData(saahandle, curr_addr, in);
}

void saa1099_ext_tick(void *userdata, uint8_t *stream, int len){
    SAASNDGenerateMany(saahandle, stream, len/4);


}
