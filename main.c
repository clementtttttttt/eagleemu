#include <SDL.h>
#include "cpu.h"
#include <math.h>
#include <pthread.h>
#include "gfx.h"
#include "keyb.h"
#include <stdbool.h>
#include <SDL_ttf.h>
#include <unistd.h>
#include <stdio.h>
#include <fcntl.h>
#include "saa1099_ext.h"
#include <SDL_mixer.h>
#include <termio.h>
#include "serial.h"
// Window size
#define WINDOW_WIDTH 640
#define WINDOW_HEIGHT 640

uint32_t* screen;
extern int in_vblank;
double clamp(double d, double min, double max) {
  const double t = d < min ? min : d;
  return t > max ? max : t;
}
extern pthread_mutex_t serial_lock;
int term_fd;

TTF_Font * fon;
SDL_Renderer *renderer;
   char *serdev_name=0;
    char *aqxe_name=0;

const int CPU_FREQ = 6293750;
void draw_text(uint8_t r,uint8_t g, uint8_t b, uint8_t a, char *text ,int x, int y, int sz,int wrap){


        int char_w, char_h;
        TTF_SizeText(fon,"A", &char_w, &char_h);

        SDL_Surface *dbgtext;
        if(wrap != 0){
            dbgtext = TTF_RenderText_Solid_Wrapped(fon, text, (SDL_Color){r,g,b,a}, wrap*char_w);
        }
        else{
            dbgtext =  TTF_RenderText_Solid(fon, text, (SDL_Color){r,g,b,a});

        }
        SDL_Rect area = {x, y, dbgtext->w* sz/10, dbgtext->h* sz/ 10};

        SDL_Texture *texttex = SDL_CreateTextureFromSurface(renderer, dbgtext);
        SDL_RenderCopy(renderer, texttex, NULL, &area);
        SDL_DestroyTexture(texttex);
        SDL_FreeSurface(dbgtext);

}

int main(int argc, char* argv[])
{
    if(argc < 2){
        printf("usage: eagleemu [serial_dev] (-a [.aqxe file])\n");
        return -1;

    }
            pthread_mutex_init(&serial_lock,NULL);



    for(int i=1; i<argc; ++i){

        if (*((short*)(argv[i])) == 'a-'){
            ++i;
            if(i>=argc){
                printf(".aqxe file not specified after -a option\n");
                return -1;
            }
            aqxe_name = argv[i];

            continue;
        }

        if(!serdev_name){
            serdev_name = argv[i];
        }
        else{
            printf("Unrecognised argument %s\n", argv[i]);
            exit(-1);
        }


    }

    term_fd=open(serdev_name,O_RDWR|O_NONBLOCK);

    if(term_fd == -1){
        perror("Failed to open vterm: ");
        return -1;
    }

    struct termios t;
    tcgetattr(term_fd, &t);
    t.c_cflag |= CRTSCTS;
    tcsetattr(term_fd,TCSANOW, &t);

    // SDL initialisation
    if (SDL_Init(SDL_INIT_EVERYTHING) != 0)
    {
        SDL_Log("SDL_Init Error: %s\n", SDL_GetError());
        return -1;
    }


    // Window creation and position in the center of the screen
    SDL_Window* window = SDL_CreateWindow("Eagle-88 emulator", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, WINDOW_WIDTH, WINDOW_HEIGHT, SDL_WINDOW_SHOWN);
    if (window == NULL)
    {
        SDL_Log("SDL_CreateWindow Error: %s\n", SDL_GetError());
        return -1;
    }

    renderer = SDL_CreateRenderer(window, -1,SDL_RENDERER_ACCELERATED );

    SDL_Texture* framebuffer = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_STREAMING, 320, 480);

    // Keep the main loop until the window is closed (SDL_QUIT event)

    SDL_Init(SDL_INIT_AUDIO);
	SDL_AudioSpec spec, aspec; // the specs of our piece of "music"
	SDL_zero(spec);
	spec.freq = 44100; //declare specs
	spec.format = AUDIO_S16SYS;
	spec.channels = 2;
	spec.samples = 128;
	spec.callback = saa1099_ext_tick;
	spec.userdata = NULL;



  //Open audio, if error, print
	int id;
	if ((id = SDL_OpenAudioDevice(NULL, 0, &spec, &aspec, SDL_AUDIO_ALLOW_ANY_CHANGE)) <= 0 )
	{
	  fprintf(stderr, "Couldn't open audio: %s\n", SDL_GetError());
	  exit(-1);
	}
	    saa1099_ext_init();


	/* Start playing, "unpause" */
	SDL_PauseAudioDevice(id, 0);

    screen = malloc(320*480*sizeof(uint32_t));

    pthread_t system_thread;
    int err = pthread_create(&system_thread, NULL, system_func, NULL);

    if(err){
        printf("%s %s\n","error happened while creating thread\n", "");
        exit(1);
    }

    TTF_Init();
     fon = TTF_OpenFont("default.ttf",16);

    fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK); //serial read


    bool exit = false;
    SDL_Event eventData;

    extern uint64_t ticks;
    extern uint64_t ips;

    uint32_t frames = 0;
    uint32_t framei = 0;

    char mhzstring[100];

    gfx_init_vram();

    unsigned int b = 0;
    int lctrl=0;
    while (!exit)
    {
        b=SDL_GetTicks();



        SDL_RenderClear(renderer);
        while (SDL_PollEvent(&eventData))
        {
            switch (eventData.type)
            {
            case SDL_QUIT:
                exit = true;
                break;
                case SDL_KEYDOWN:
                    if(lctrl){
                        if(eventData.key.keysym.sym == SDLK_r){
                            cpu_reset();
                        }
                    }
                    if(eventData.key.keysym.sym == SDLK_LCTRL) {lctrl = 1;}
                    ps2_encode(eventData.key.keysym.scancode,true);
                break;
                case SDL_KEYUP:
                    if(eventData.key.keysym.sym == SDLK_LCTRL) {lctrl = 0;}
                    ps2_encode(eventData.key.keysym.scancode,false);

                break;
            }
        }


        SDL_UpdateTexture(framebuffer, NULL, screen, 320 * sizeof (Uint32));

        gfx_clear();

        gfx_reset_ptr();








        if(SDL_GetTicks() - frames >= 125){


            sprintf(mhzstring, "%01.6lf MHZ %02d FPS %01.6lf MIPS",((double)ticks)*4*2/1000000, framei*4*2, ((double)ips)*4*2/1000000);
            frames = SDL_GetTicks();

	   extern int in_hlt;
	   	if(!in_hlt){
            extern uint32_t waitloop_ticks;
                waitloop_ticks += clamp(sinh(((int)ticks - (int)(CPU_FREQ/2/2/2))/69999),-10,10);
                waitloop_ticks = clamp((int)waitloop_ticks, 0, DBL_MAX);
		}

           // printf("wait: %d\n",waitloop_ticks);


            framei = 0;
                        ticks=0;
                        ips = 0;

        }

        SDL_Rect scrn_dest = {0,0,640,480};
        SDL_RenderCopy(renderer, framebuffer, NULL, &scrn_dest);

        //debug registers
        SDL_Rect debugleds = {0,480,16,16};

        for(int i=0;i<8; ++i){
            SDL_SetRenderDrawColor(renderer,!!((cpu_get_debug_reg() << i) & 0x80) * 0x88+ 0x50,0,0,0xff);
            SDL_RenderFillRect(renderer, &debugleds);
            debugleds.x += 20;
        }
        SDL_SetRenderDrawColor(renderer,0x0,0,0,0xff);

        draw_text(0xff,0xff,0xff,0xff,"0xC0000 DEBUG LEDS", 0, debugleds.y+=15,6, 0);



        draw_text(0xff, 0xff, 0xff, 0xff, mhzstring, 320, 480,8, 20);


        draw_text(0xff, 0xff, 0xff, 0xff, cpu_dump_debug(), 0, debugleds.y += 15, 10,33);
        draw_text(0xff, 0xff, 0xff, 0xff, cpu_dump_flags_debug(), 0, debugleds.y += 15*5, 10,33);
                		in_vblank = 1;

        SDL_RenderPresent(renderer);



                cpu_hw_start_int(0); // VSYNC
        SDL_Delay(4);

                unsigned char k;
        if((k = key_pop_buf())){
            key_set_buf(k);
            cpu_hw_start_int(3);
        }
        		in_vblank = 0;

                        if((1000 / 58 - SDL_GetTicks() + b) < 400 )
                SDL_Delay(1000 / 58 - SDL_GetTicks() + b);
        serial_tick();
        ++framei;

    }
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
