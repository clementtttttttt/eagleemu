#include <stdio.h>
#include "cpu.h"
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/poll.h>
#include <termios.h>
#include <pthread.h>
unsigned char serial_regs[8] = {0,0,0,0,0,0<<5,0b01100000,0}; // 0 = receive reg, 6 = lsr
unsigned char serial_tx_reg=0; //set to 0 after transmit
unsigned short serial_divisor = 1; // baud divisor
int loopback_reg=0x0;
pthread_mutex_t serial_lock;

int not_read = 0;
extern int term_fd;

unsigned char* serial_get_regs(unsigned char addr){


    if((serial_regs[3] & 0x80) && addr < 2){

        return &((unsigned char*)&serial_divisor)[addr];
    }

      pthread_mutex_lock(&serial_lock);

    if(addr == 0 && (serial_regs[5] & 1)){
        unsigned int c=0;

        int ret = read(term_fd,&c,1);

        serial_regs[0]=c;
        serial_regs[5]&=~1;

    }


        pthread_mutex_unlock(&serial_lock);



    return &(serial_regs[addr]);
}

void serial_write_regs(unsigned char addr, unsigned char dat){
addr &= 0b111;
    if((serial_regs[3] & 0x80) && addr < 2){
        ((unsigned char*)&serial_divisor)[addr&0b1] = dat;
        return;
    }
    switch(addr & 0x7){
        case 0:
            unsigned char bits = 8 - ((serial_regs[3] & 0b11) + 5);
            unsigned char mask = 0xff >> bits;
            dat  &= mask;
            serial_tx_reg = dat;
            serial_regs[6] &= ~(0b100000);
            serial_regs[5] &= ~((1 << 5) | (1 << 6));
            serial_regs[5] |= (1 << 5) | (1 << 6);

            write(term_fd, &serial_tx_reg, 1);
         //   wprintw(win,"TEST: %x %x", segregs[cs],ip);
            if(serial_regs[4] & 0b10000){
            //loopback            usleep(serial_divisor * 9 );

            printf("SERIAL LOOPBACK\n");
            loopback_reg = 0x100 | dat;
            }
                        serial_tx_reg = 0;

        if(serial_regs[1] & 0b10){
            cpu_hw_start_int(1);
        }
            return;
        break;
        case 4:
        {
  /*          int serstat;
            ioctl(term_fd, TIOCMGET,&serstat);
            if(dat & 0x2){
                serstat |= TIOCM_RTS;
            }
            else{
                serstat &= ~TIOCM_RTS;
            }
            ioctl(term_fd, TIOCMSET, &serstat);*/
        }

    }
    serial_regs[addr & 0b111] = dat;

}
extern union flags_t flags_reg;
void serial_tick(){


    struct pollfd p;
    p.fd=term_fd;
    p.events=POLLIN;



    while((((serial_regs[4] & 2)&&!(serial_regs[5]&1)) || loopback_reg&0x100)){


        int ret = poll(&p, 1, 0);
        if(ret == -1 ){

            break;
        }
        if(!(p.revents & POLLIN)){

            break;
        }
          pthread_mutex_lock(&serial_lock);

        p.revents = 0;

        loopback_reg = 0;

        serial_regs[5] |= 0b1;


        if(serial_regs[1] & 1){
            cpu_hw_start_int(1);
        }

                      pthread_mutex_unlock(&serial_lock);



        usleep(serial_divisor*9*8*20);

    }

}
