#include "sd.h"
#include <stdio.h>
#include <string.h>
static unsigned char out_reg=0x00;
static unsigned char out_stor_reg = 0x00;
unsigned char init_count = 74;
unsigned char sd_get_shiftreg(){

    return out_stor_reg;
}
static unsigned char old_ctrl = 0;

static unsigned char transmit_count = 0;
static unsigned char in_transmit = 0;

static unsigned long long command_ret = 0xffffffffffffffff;
unsigned long long command_ret_count = 0;

char command_ret_end=1;

unsigned long long sd_shift_reg = 0xffffffffffffffff;

unsigned char idle_state = 1;
unsigned char next_is_app = 0;

static unsigned int sd_read = 0;

static unsigned char read_buf[515];


void sd_tick(unsigned char ctrl){
    if((ctrl & 0b100) && !(old_ctrl & 0b100)){ //clock transitions to high (sdcard)
        if(init_count && (ctrl & 0b10 /*chip select is high*/) && (ctrl & 0b1000 /*byte 0xff*/)){
            --init_count; //yes init
            if(init_count == 0){
             printf("[EMU] SD INIT COMPLETE\r\n");
            }
        }
        else{
            //actually do sd card logic
            //shift reg
                            if(!init_count)
                sd_shift_reg <<= 1;
            if(ctrl & 0b1000){
                sd_shift_reg |= (unsigned long long)1;
            }else{
                sd_shift_reg &= ~(unsigned long long)1;
            }



            if(((sd_shift_reg) & 0b11)==0b01 && !in_transmit){ //start of transmission
                transmit_count = 46; //6 bytes - 2
                in_transmit = 1;
            }

            if((transmit_count == 0 && in_transmit)){
                //do command or whatever
                if(!next_is_app){
                unsigned char chk = ((sd_shift_reg>>8) & 0xff);
                switch ((sd_shift_reg >> 40 )& 0x3f){
                    case 0:
                        command_ret = 0xff01ffffffffffff; //normal idle state plus wait code
                        command_ret_count = 16;

                    break;
                    case 8:
                        command_ret = 0xff010000010087ff;//cmd8 return val
                        command_ret |= ((unsigned long)chk) << 16; //check pattern
                        command_ret_count = 48;
                    break;
                    case 55:
                        command_ret = 0xff00ffffffffffff; //normal idle state plus wait code
                        command_ret |= ((unsigned long long)idle_state << 48);
                        command_ret_count = 16;
                        next_is_app = 1;
                    break;
                    case 59:
                        command_ret = 0xff00ffffffffffff; //normal idle state plus wait code
                        command_ret_count = 16;
                        command_ret |= ((unsigned long long)idle_state << 48);
                    break;
                    case 16: //set blksize, treat as noop because fuck it
                        command_ret = 0xff00ffffffffffff; //normal idle state plus wait code
                        command_ret_count = 16;
                        command_ret |= ((unsigned long long)idle_state << 48);
                    break;
                    case 58:
                        command_ret = 0xff00c0ff8000ffff; //OCR reg, all voltages busy and ready
                        command_ret_count = 8 * 6; //6 bytez
                    break;
                    case 17: // read

                        command_ret = 0xff00ffffffffffff;
                        command_ret_count = 16;
                        sd_read = 515*8;

                        //handle single block read
                        memset(read_buf, 0, 515);
                        read_buf[0] = 0xfe;
                        read_buf[513] = 0;
                        read_buf[514] = 0;
                        FILE *sdcard = fopen("sd.img", "rb");

                        if(sdcard){
                            fread(read_buf+1, 1,512, sdcard);
                        }
                        fclose(sdcard);

                    break;
                    }
                }
                else{
                    //ACMD
                    switch ((sd_shift_reg >> 40 )& 0x3f){
                        case 41: //ACMD41
                            command_ret = 0xff00feffffffffff; //normal idle state plus wait code
                            command_ret_count = 24;
                            idle_state = 0;
                            command_ret |= ((unsigned long long)idle_state << 48);
                        break;

                    }
                            next_is_app = 0;


                }
                in_transmit = 0;

            }





        }
    }

    if(!(ctrl & 0b100) && (old_ctrl & 0b100) && !(ctrl & 0x10)){ //clock transitions to low (sdcard)

        if(!command_ret_count){


            if(sd_read){
                unsigned int sd_read2 = 515*8 - sd_read;
                unsigned char mask = 0x80 >> (sd_read2 % 8);

                if(mask & read_buf[sd_read2/8]){
                    command_ret |= 0x8000000000000000; //yes out

                }
                else{
                    command_ret &= ~0x8000000000000000;
                }
                            command_ret_end = !!(command_ret & 0x8000000000000000);

                --sd_read;
            }
            else{

                if(transmit_count)           --transmit_count;

            }
        }
        else{
            command_ret_end = !!(command_ret & 0x8000000000000000);
            command_ret <<= 1;
            --command_ret_count;
            command_ret |= 1;

        }


    }

    if((ctrl & 1) && !(old_ctrl & 1)){ //sd receive reg ticked

        out_reg <<= 1;


        if(command_ret_end){
            out_reg |= 1; //set out rge
        }
        out_stor_reg = out_reg;



    }
    old_ctrl = ctrl;

}
