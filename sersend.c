#include <stdio.h>
#include <termios.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/ioctl.h>
int main(int argc, char** argv){
	if(argc != 3){
		fprintf(stderr,"Usage: %s [port] [file]\n", argv[0]);
		exit(-1);
	}

	int term_fd = open(argv[1], O_RDWR|O_SYNC);

	int file_fd = open(argv[2], O_RDWR);

	int c;
	while(read(file_fd, &c, 1)){
		int serstate;

		//im sorry
		goto skip_shit;
		do{

			printf("WAITING FOR RTS\n");

			skip_shit:
			//usleep(3000);
			usleep(900);

			if(ioctl(term_fd, TIOCMGET, &serstate)==-1){
				perror("IOCTL TIOCMGET ERROR: ");
				break;
			}
			
		}while(!!!(serstate&TIOCM_CTS));
		
		
		write(term_fd, &c, 1);
		
	}

	return 0;
	
}
