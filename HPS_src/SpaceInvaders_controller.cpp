#include <error.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <sys/time.h>
#include <signal.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <linux/input.h>
#include <pthread.h>

#define BRIDGE 0xC0000000
//#define BRIDGE_SPAN 0x48
#define BRIDGE_SPAN 0x80

#define HPS_CMD 0x0000
#define HPS_DATA 0x0040
#define FPGA_CMD 0x0010
#define FPGA_ARG1 0x0020
#define FPGA_DEBUG 0x0030

#define GAMEPAD 0x0044

#define HPS2_DATA 0x0048
#define FPGA2_REQ 0x0050


#define QUEUE_SIZE 16

#define ROM_FILENAME1 "invaders.h"
#define ROM_FILENAME2 "invaders.g"
#define ROM_FILENAME3 "invaders.f"
#define ROM_FILENAME4 "invaders.e"

#define ROM_FILENAME5 "invadermove1.wav"
#define ROM_FILENAME6 "invadermove2.wav"
#define ROM_FILENAME7 "invadermove3.wav"
#define ROM_FILENAME8 "invadermove4.wav"
#define ROM_FILENAME9 "shot.wav"
#define ROM_FILENAME10 "invaderkilled.wav"
#define ROM_FILENAME11 "playerdied.wav"
#define ROM_FILENAME12 "ufo.wav"
#define ROM_FILENAME13 "ufohit.wav"
#define ROM_FILENAME14 "extendedplay.wav"

#define ROM_DIR "/root/roms/space_invaders/"

static volatile int keepRunning = 1;

static volatile uint16_t hps_reqId=0;

static volatile uint8_t* sdop_map = NULL;
static volatile uint8_t* sddata_map = NULL;
static volatile uint8_t* sdreqId_map = NULL;
static volatile uint8_t* hps2_map = NULL;
static volatile uint8_t* fpga2_map = NULL;

/***** Commandes FPGA *****
 * File for test: mario-mono.dat
 * 1: Get number files in roms directory
 * 2: Get names of files
 * 3: Open file and start read 2 chars or continue reading
 * 31: Open file and start read 1 char or continue reading
 * 34: Open file and start read 4 chars or continue reading
 * 4: Close file
 * 5: Stop All
 * 6: Select file and return size of this file
 ***************************/

/***** Signaux HPS *****
 * 1: SD Card ready
 * 2: Return number of files in directory "/root/roms/space_invaders"
 * 3: Return size of given file
 * 5: Return 2 chars from file content
 * 7: Waiting for new request
 * 8: Return file size
 * 9: Return 1 char from file content
 * 10: Return 4 chars from file content
 ************************/

void intHandler(int dummy) {
    keepRunning = 0;
}

typedef struct {
    size_t head;
    size_t tail;
    size_t size;
    void** data;
} queue_t;

struct filer2_arg_struct {
    uint8_t* hps2_map;
    uint8_t* fpga2_map;
};

size_t queue_count(queue_t *queue) {
	return queue->head - queue->tail;
}

void* queue_read(queue_t *queue) {
    if (queue->tail == queue->head) {
        return NULL;
    }
    void* handle = queue->data[queue->tail];
    queue->data[queue->tail] = NULL;
    queue->tail = (queue->tail + 1) % queue->size;
    return handle;
}

int queue_write(queue_t *queue, void* handle) {
    if (((queue->head + 1) % queue->size) == queue->tail) {
        return -1;
    }
    queue->data[queue->head] = handle;
    queue->head = (queue->head + 1) % queue->size;
    return 0;
}

void setMapValue(int map_ptr,int map_value) {
    if(map_ptr == 0) *((uint16_t *)sdop_map) = (uint16_t) map_value;
    else if(map_ptr == 1) *((uint32_t *)sddata_map) = map_value;
    else printf("setMapValue impossible for map_ptr %d\n",map_ptr);
}

void *thread_gamepad(void *data) {
	pthread_t tid;
	uint8_t* gamepad_map = (uint8_t *)data;

	// La fonction pthread_self() renvoie
	// l'identifiant propre à ce thread.
	tid = pthread_self();
	printf("Thread [%lu] running\n",(unsigned long)tid);

	//Process for Gamepad
	int fd2 = open("/dev/input/event0",O_RDONLY);
	if(fd2 < 0){
		perror("Couldnt open event0.");
		return (NULL);
	}

	ssize_t bytes;
	struct input_event ev;
	int axeVal;
	int axeDir; 
	while(keepRunning){
		bytes = read(fd2, &ev, sizeof(ev));
		if(bytes == sizeof(ev)){
			if(ev.type == EV_KEY){
				printf("Button %u %s\n", ev.code, ev.value ? "pressed" : "released");
				*((uint32_t *)gamepad_map) =  ((2 + 1*ev.value) << 9) + ev.code;//3 + 190 => A pressée / 2 + 190 => A relachée
			}
			else if(ev.type == EV_ABS){
				printf("Axe %u valeur %d\n", ev.code, ev.value);
				axeVal = ev.value;
				if(ev.value < 0) axeVal += 512;

				if(ev.code == 16) axeDir=0;
				else axeDir=1;
				*((uint32_t *)gamepad_map) = (axeDir << 9) + axeVal;
				////queue_write(queue_gamepad, (void*)(ev.value));
			}
		}
	}

	close(fd2);

	printf("Thread [%lu] stopped\n",(unsigned long)tid);

	return (NULL); // Le thread termine ici.
}

void *thread_filer2(void *data) {
	pthread_t tid;

	/*uint8_t* bridge_map = (uint8_t *)data;

	uint8_t* hps2_map = NULL;
	uint8_t* fpga2_map = NULL;

	hps2_map = bridge_map + HPS2_DATA;
	fpga2_map = bridge_map + FPGA2_REQ;*/

	uint32_t fReq;
	int8_t fCmd;
	uint32_t fArg1;
	int fArg1_cur;
	uint8_t opNum = 1;//1 => Filer2 ready
	uint32_t opData = 0;

	/*struct filer2_arg_struct *filer2_args = (struct filer2_arg_struct *)data;

	uint8_t* hps2_map = filer2_args->hps2_map;
	uint8_t* fpga2_map = filer2_args->fpga2_map;*/

	// La fonction pthread_self() renvoie
	// l'identifiant propre à ce thread.
	tid = pthread_self();
	printf("Thread filer2 [%lu] running\n",(unsigned long)tid);

	struct dirent *dir;
	struct timeval time;
	struct stat st;
	char filenameSel[64];
	int pause_ena;
	int nbRead;
	
	while(keepRunning){
		*((uint32_t *)hps2_map) = opNum + (opData << 8);

		fReq = *((int *)fpga2_map);

		fCmd = fReq & 0xff;
		fArg1 = fReq >> 8;

		pause_ena = 2000;//ms

		if(fCmd != 5){
			printf("(FILER2) OP%d FCMD : %d / ARG1 : %d\n",opNum,fCmd,fArg1);
			//printf("FDEBUG : %d\n",fDebug);
		}

		if(fCmd == 6){//Get filesize of file "/root/roms/space_invaders/" + ROM_FILENAME{X}
			printf("(FILER2) File num requested: %d\n",fArg1);

			memset(filenameSel,0,64);
			strcpy(filenameSel,ROM_DIR);
			if(fArg1 == 1) strcat(filenameSel,ROM_FILENAME1);
			else if(fArg1 == 2) strcat(filenameSel,ROM_FILENAME2);
			else if(fArg1 == 3) strcat(filenameSel,ROM_FILENAME3);
			else if(fArg1 == 4) strcat(filenameSel,ROM_FILENAME4);
			else if(fArg1 == 5) strcat(filenameSel,ROM_FILENAME5);
			else if(fArg1 == 6) strcat(filenameSel,ROM_FILENAME6);
			else if(fArg1 == 7) strcat(filenameSel,ROM_FILENAME7);
			else if(fArg1 == 8) strcat(filenameSel,ROM_FILENAME8);
			else if(fArg1 == 9) strcat(filenameSel,ROM_FILENAME9);
			else if(fArg1 == 10) strcat(filenameSel,ROM_FILENAME10);
			else if(fArg1 == 11) strcat(filenameSel,ROM_FILENAME11);
			else if(fArg1 == 12) strcat(filenameSel,ROM_FILENAME12);
			else if(fArg1 == 13) strcat(filenameSel,ROM_FILENAME13);
			else if(fArg1 == 14) strcat(filenameSel,ROM_FILENAME14);
			else{
				keepRunning=0;
				printf("!!! (FILER2)  ALERT: not file num %d existing\n",fArg1);
			}

			if(keepRunning){
				stat(filenameSel, &st);
				opData = st.st_size;

				printf("(FILER2) Size of file %s : %d\n",filenameSel,opData);
				opNum = 8;
			}

			pause_ena = 100;
		}
		else if(fCmd == 3 || fCmd == 31){//Request to get content of file ROM_DIR + ROM_FILENAME{X}
			if(fCmd == 3) opNum = 5;//Send 2 chars from file content
			else opNum = 9;//Send 1 char from file content

			nbRead = 0;
			fArg1_cur = -1;

			printf("(FILER2) open %s\n",filenameSel);
			int fdFiler = open(filenameSel, O_RDONLY);

			struct stat stFiler;
			fstat(fdFiler, &stFiler);
			size_t sizeFiler = stFiler.st_size;

			char *dataFiler = (char*)mmap(NULL, sizeFiler, PROT_READ, MAP_PRIVATE, fdFiler, 0);

			bool opNumChanged = false;
			
			while(keepRunning){
				if((fArg1_cur != fArg1) || (opNumChanged)){
					fArg1_cur = fArg1;

					if(opNum == 5){
						*((uint32_t *)hps2_map) = opNum + (dataFiler[fArg1_cur + 1] << 16) + (dataFiler[fArg1_cur] << 8);
					}
					else{
						*((uint32_t *)hps2_map) = opNum + (dataFiler[fArg1_cur] << 8);
					}

					fReq = *((int *)fpga2_map);
					fCmd = fReq & 0xff;
					fArg1 = fReq >> 8;

					/*if(nbRead < 20){
						printf("(FILER2) value at %d => %04x | fArg1 Next: %d\n",fArg1_cur,dataFiler[fArg1_cur],fArg1);
					}*/

					nbRead++;
				}
				else{//On se met en attente
					////if(nbRead < 20) printf("(FILER2) Waiting - fCmd: %d | fArg1: %d\n",fCmd,fArg1);//A commenter
					
					fReq = *((int *)fpga2_map);
					fCmd = fReq & 0xff;
					fArg1 = fReq >> 8;
				}

				if(fCmd == 4) break;//End read

				if(fCmd == 3){//Send 2 chars from file content
					if(opNum != 5){
						opNum = 5;
						//*((uint16_t *)sdop_map) = opNum;
						opNumChanged = true;
					}
					else if(opNumChanged) opNumChanged = false;
				}
				else opNum = 9;//Send 1 char from file content

				//if(nbRead <= 20) printf("(FILER2) opNum: %d | fCmd: %d | fArg1: %d\n",opNum,fCmd,fArg1);//A commenter
			}

			printf("(FILER2) end send file data\n");
			
			munmap(dataFiler, sizeFiler);
			close(fdFiler);

			opNum = 6;
			pause_ena = 0;
		}
		else if(fCmd == 5){
			opNum = 7;//Waiting for new action
			opData = 0;
			pause_ena = 100;
			//pause_ena = 1000;
		}
		else{ //fCmd inconnu
			printf("!!! (FILER2)  fCmd unknown: %d\n",fCmd);
			pause_ena = 2000;
		}

		if(pause_ena) usleep(pause_ena*1000);
	}

	printf("Thread filer2 [%lu] stopped\n",(unsigned long)tid);

	return (NULL); // Le thread termine ici.
}

int main(int argc, char** argv) {
	//using namespace boost::multiprecision;

	pthread_t tid1; // Identifiant du thread Gamepad
	pthread_t tid2; // Identifiant du thread Filer2

	uint16_t opNum = 0;
	int sddata = 0;
	//uint16_t hps_reqId=0;
	uint16_t fCmd = 0;
	int fArg1 = 0;
	int fDebug = 0;
	int fArg1_cur;
	int gamepad = 0;
	int filer = 0;

	int files_count = 0;
	int count = 0;
	int fileName_len;
	char filename[256];
	int i;
	char line[10];
	int audio_sample=0;

	fpos_t pos;

	struct dirent *dir;
	struct timeval time;
	struct stat st;
	char filenameSel[64];

	//char full_filename[256];
    //strcpy(full_filename,ROM_DIR);
	//strcat(full_filename,ROM_FILENAME);

	signal(SIGINT, intHandler);

	printf("Display roms list\n");

	DIR *d = opendir(ROM_DIR); 
	if (d){
		while ((dir = readdir(d)) != NULL) {
			fileName_len = strlen(dir->d_name);

			if(fileName_len > 4){
				//if( (dir->d_name[fileName_len - 1] == 'v' && dir->d_name[fileName_len - 2] == 'a')){
				if( strcmp(dir->d_name,ROM_FILENAME1) == 0 || strcmp(dir->d_name,ROM_FILENAME2) == 0 || strcmp(dir->d_name,ROM_FILENAME3) == 0 || strcmp(dir->d_name,ROM_FILENAME4) == 0 ){
					files_count++;
					printf("%s\n", dir->d_name);
					//printf("name size: %d\n",strlen(dir->d_name));
				}
			}
		}
		closedir(d);
	}

	printf("Roms list done (files_count: %d)\n",files_count);
	//usleep(500*1000);

	int fd = 0;

	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) {
		perror("Couldn't open /dev/mem\n");
		return -2;
	}

	uint8_t* bridge_map = NULL;

	bridge_map = (uint8_t*)mmap(NULL, BRIDGE_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd, BRIDGE);

	if (bridge_map == MAP_FAILED) {
		perror("Couldn't map bridge.");
		close(fd);
		return -3;
	}

	printf("bridge_map created\n");
	usleep(500*1000);

	//uint8_t* sddata_map = NULL;
	//uint8_t* sdop_map = NULL;
	//uint8_t* sdreqId_map = NULL;
	uint8_t* sdcmd_map = NULL;
	uint8_t* sdarg1_map = NULL;
	uint8_t* sddebug_map = NULL;
	uint8_t* gamepad_map = NULL;
	

	sddata_map = bridge_map + HPS_DATA;
	sdop_map = bridge_map + HPS_CMD;
	sdcmd_map = bridge_map + FPGA_CMD;
	sdarg1_map = bridge_map + FPGA_ARG1;
	sddebug_map = bridge_map + FPGA_DEBUG;
	gamepad_map = bridge_map + GAMEPAD;
	hps2_map = bridge_map + HPS2_DATA;
	fpga2_map = bridge_map + FPGA2_REQ;

	opNum = 1;//1 => sd ready / 2 => Nb files
	int hData=0;
	printf("Press Ctrl + C to quit\n");
	gettimeofday(&time, NULL);
	unsigned long microsec = (time.tv_sec * 1000000) + time.tv_usec;
	printf("start communication ==> %lu\n",microsec);

	int pause_ena;
	uint16_t fCmd_prev;
	int nbRead;

	/*struct filer2_arg_struct filer2_args;

	filer2_args.hps2_map = hps2_map;
	filer2_args.fpga2_map = fpga2_map;*/

	// Création du premier thread qui va directement aller
	 // exécuter sa fonction thread_gamepad.
	//queue_t queue_gamepad = {0, 0, QUEUE_SIZE, (void**)malloc(sizeof(void*) * QUEUE_SIZE)};
	pthread_create(&tid1, NULL, thread_gamepad, gamepad_map);
	//pthread_create(&tid2, NULL, thread_filer2, (void *)&filer2_args);
	pthread_create(&tid2, NULL, thread_filer2, bridge_map);

	printf("Main: Creation du thread Gamepad [%lu]\n", (unsigned long)tid1);
	printf("Main: Creation du thread Filer2 [%lu]\n", (unsigned long)tid2);
	void* gamepadHandle;

	if(true){
		// Process for SD Controller
		while(keepRunning){
			setMapValue(0,opNum);
			if(opNum != 1) setMapValue(1,hData);
			else setMapValue(1,670);//Ici on passe une valeur pour faire du deboggage dans l'opcode
			//else setMapValue(1,0);//Obligatoire sinon le waitrequest n'est jamais déclenché

			fCmd = *((uint16_t *)sdcmd_map);
			fArg1 = *((int *)sdarg1_map);
			fDebug = *((int *)sddebug_map);
			
			if(fCmd != 5){
				printf("REQID%d OP%d FCMD : %d / ARG1 : %d / FDEBUG: %d\n",hps_reqId,opNum,fCmd,fArg1,fDebug);
				//printf("FDEBUG : %d\n",fDebug);
			}

			pause_ena = 1000;//ms

			if(fCmd == 1) {//Request to get number of files in roms directory
				opNum = 2;
				files_count=0;

				DIR *d = opendir(ROM_DIR); 
				if (d){
					while ((dir = readdir(d)) != NULL) {
						fileName_len = strlen(dir->d_name);

						if(fileName_len > 4){
							if( strcmp(dir->d_name,ROM_FILENAME1) == 0 || strcmp(dir->d_name,ROM_FILENAME2) == 0 || strcmp(dir->d_name,ROM_FILENAME3) == 0 || strcmp(dir->d_name,ROM_FILENAME4) == 0 ){
								files_count++;
								//printf("%s\n", dir->d_name);
							}
						}
					}
					closedir(d);
				}

				hData = files_count;
				printf("GET NUMBER OF FILES : %d\n",files_count);
				pause_ena = 500;
			}
			else if(fCmd == 2) {//Request to get name of file at given pos
				printf("GET FILENAME NUM : %d\n",fArg1);

		        opNum = 3;
				d = opendir(ROM_DIR);
				if (d){
					i = 0;
					while ((dir = readdir(d)) != NULL) {
						fileName_len = strlen(dir->d_name);
						if(fileName_len > 4){
							if( (dir->d_name[fileName_len - 1] == 'v' && dir->d_name[fileName_len - 2] == 'a')) {
								if(i == fArg1){
									strcpy(filename,dir->d_name);
									filename[fileName_len] = '\0';
									break;
								}
								i++;
							}
						}
					}
					closedir(d);
				}
				
				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("start send name %s: %lu\n",filename,microsec);
				for(i=0; i < 100;i++){
					if(filename[i] == '\0'){
						//Avant de sortie, on ajoute un saut de ligne pour l'affichage sur l'écran
						setMapValue(0,i*16 + opNum);//i*16 pour decaler 4 fois a gauche
						setMapValue(1,'\0');
						
						fCmd = *((uint16_t *)sdcmd_map);
						fDebug = *((int *)sddebug_map);
						//printf("OP3 FCMD : %d\n",fCmd);
						//printf("OP3 FDEBUG : %d\n",fDebug);

						break;
					}

					setMapValue(0,i*16 + opNum);
					setMapValue(1,filename[i]);

					fCmd = *((uint16_t *)sdcmd_map);
					fDebug = *((int *)sddebug_map);
					//printf("OP3 FCMD : %d\n",fCmd);
					//printf("OP3 FDEBUG : %d\n",fDebug);
				}
				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("end send name: %lu\n",microsec);

				opNum = 4;//Send signal end filename
				pause_ena = 0;
			}
			else if(fCmd == 3 || fCmd == 31 || fCmd == 34){//Request to get content of file ROM_DIR + ROM_FILENAME{X}
				if(fCmd == 3) opNum = 5;//Send 2 chars from file content
				else if(fCmd == 34) opNum = 10;//Send 4 chars from file content
				else opNum = 9;//Send 1 char from file content

				fDebug=-1;
				nbRead = 0;
				fArg1_cur = -1;

				printf("open %s\n",filenameSel);
				int fdFiler = open(filenameSel, O_RDONLY);

				struct stat stFiler;
				fstat(fdFiler, &stFiler);
				size_t sizeFiler = stFiler.st_size;

				char *dataFiler = (char*)mmap(NULL, sizeFiler, PROT_READ, MAP_PRIVATE, fdFiler, 0);

				bool opNumChanged = false;
				//fgetpos(fp,&pos);
				
				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("start send file data: %lu\n",microsec);

				//*((uint16_t *)sdop_map) = opNum;
				
				while(keepRunning){
					if((fArg1_cur != fArg1) || (opNumChanged)){//Pas très propre, on pourrait faire ça plus proprement en utilisant un 2ème bridge qui serait synchro avec l'horloge du FPGA
						fArg1_cur = fArg1;

						if(opNum == 5){
							*((int *)sddata_map) = (dataFiler[fArg1_cur + 1] << 8) + dataFiler[fArg1_cur];
						}
						else if(opNum == 10){
							*((int *)sddata_map) = (dataFiler[fArg1_cur + 1] << 24) + (dataFiler[fArg1_cur + 1] << 16) + (dataFiler[fArg1_cur + 1] << 8) + dataFiler[fArg1_cur];
						}
						else{
							//*((int *)sddata_map) = dataFiler[fArg1_cur];
							*((uint16_t *)sdop_map) = opNum;
							setMapValue(1,dataFiler[fArg1_cur]);
						}

						fCmd = *((uint16_t *)sdcmd_map);
						fArg1 = *((int *)sdarg1_map);
						fDebug = *((int *)sddebug_map);

						if(nbRead < 10){
							printf("value at %d => %04x | fArg1 Next: %d\n",fArg1_cur,dataFiler[fArg1_cur],fArg1);
						}

						/*if(fArg1_cur % 10000 == 0){
							printf("value at %d => %s (%d chars)\n",fArg1_cur,line,count);
							printf("value from fpga => %d\n",fDebug);
						}*/
						nbRead++;
					}
					else{//On se met en attente
						//if(nbRead < 400) printf("Waiting - fCmd: %d | fArg1: %d | fDebug: %d\n",fCmd,fArg1,fDebug);//A commenter
						if(nbRead < 20) printf("Waiting - fCmd: %d | fArg1: %d\n",fCmd,fArg1);//A commenter
						//setMapValue(0,opNum);//opNum ne change pas
						
						fCmd = *((uint16_t *)sdcmd_map);
						fArg1 = *((int *)sdarg1_map);
						fDebug = *((int *)sddebug_map);
						//nbRead++;
					}

					if(fCmd == 4) break;//End read

					if(fCmd == 3){//Send 2 chars from file content
						if(opNum != 5){
							opNum = 5;
							*((uint16_t *)sdop_map) = opNum;
							opNumChanged = true;
						}
						else if(opNumChanged) opNumChanged = false;
					}
					else if(fCmd == 34){//Send 4 chars from file content
						if(opNum != 10){
							opNum = 10;
							*((uint16_t *)sdop_map) = opNum;
							opNumChanged = true;
						}
						else if(opNumChanged) opNumChanged = false;
					}
					else opNum = 9;//Send 1 char from file content

					//if(nbRead <= 50) printf("opNum: %d | fCmd: %d | fArg1: %d | fDebug: %d\n",opNum,fCmd,fArg1,fDebug);//A commenter
					//if(nbRead <= 400) printf("fCmd: %d | fArg1: %d\n",fCmd,fArg1);//A commenter
				}

				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("end send file data: %lu\n",microsec);
				printf("Debug fArg1: %d\n",fArg1);

				//fclose(fp);
				munmap(dataFiler, sizeFiler);
				close(fdFiler);

				opNum = 6;
				pause_ena = 0;
				//*((int *)sddata_map) = 0;
		        //*((uint16_t *)sdop_map) = opNum;
			}
			else if(fCmd == 5){//Pending action
				opNum = 7;//Waiting for new action
				pause_ena = 100;
			}
			else if(fCmd == 6){//Get filesize of file "/root/roms/space_invaders/" + ROM_FILENAME{X}
				printf("File num requested: %d\n",fArg1);

				memset(filenameSel,0,64);
				strcpy(filenameSel,ROM_DIR);
				if(fArg1 == 1) strcat(filenameSel,ROM_FILENAME1);
				else if(fArg1 == 2) strcat(filenameSel,ROM_FILENAME2);
				else if(fArg1 == 3) strcat(filenameSel,ROM_FILENAME3);
				else if(fArg1 == 4) strcat(filenameSel,ROM_FILENAME4);
				else if(fArg1 == 9) strcat(filenameSel,ROM_FILENAME9);
				else if(fArg1 == 10) strcat(filenameSel,ROM_FILENAME10);
				else if(fArg1 == 11) strcat(filenameSel,ROM_FILENAME11);
				else if(fArg1 == 12) strcat(filenameSel,ROM_FILENAME12);
				else if(fArg1 == 13) strcat(filenameSel,ROM_FILENAME13);
				else if(fArg1 == 14) strcat(filenameSel,ROM_FILENAME14);
				else{
					keepRunning=0;
					printf("!!! ALERT: not file num %d existing\n",fArg1);
				}

				if(keepRunning){
					stat(filenameSel, &st);
					hData = st.st_size;

					printf("Size of file %s : %d\n",filenameSel,hData);
					opNum = 8;
				}

				pause_ena = 100;
			}
			else if(fCmd == 9){
				opNum = 11;
				nbRead = 0;
				fArg1_cur = -1;
				
				int fdSpTe = open("/root/music/test-speed.txt", O_RDONLY);

				struct stat stSpTe;
				fstat(fdSpTe, &stSpTe);
				size_t sizeSpTe = stSpTe.st_size;
				int dataTmp;

				char *dataSpTe = (char*)mmap(NULL, sizeSpTe, PROT_READ, MAP_PRIVATE, fdSpTe, 0);
				
				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("start speed test: %lu\n",microsec);
				
				*((uint16_t *)sdop_map) = opNum;//opNum ne change pas


				while(keepRunning){
					if(fArg1_cur != fArg1){
						fArg1_cur = fArg1;
						*((int *)sddata_map) = dataSpTe[fArg1_cur];
						
						//nbRead++;
					}

					fCmd = *((uint16_t *)sdcmd_map);
					fArg1 = *((int *)sdarg1_map);

					if(fCmd == 10){//End read
						break;
					}
					/*else if(fArg1 == 2){
						fDebug = *((int *)sddebug_map);
					}*/
					//if(nbRead > 1300000) break;
				}

				nbRead = fArg1;

				gettimeofday(&time, NULL);
				microsec = (time.tv_sec * 1000000) + time.tv_usec;
				printf("end speed test: %lu\n",microsec);
				//printf("nbRead: %d | fDebug: %d\n",nbRead,fDebug);
				printf("nbRead: %d\n",nbRead);
				//printf("last data: %d\n",dataTmp);

				munmap(dataSpTe, sizeSpTe);
				close(fdSpTe);

				opNum = 6;
				pause_ena = 0;
			}

			//if(hps_reqId >= 46015) break;
			//if(hps_reqId >= 10) break;

			fCmd_prev = fCmd;
			if(pause_ena) usleep(pause_ena*1000);
		}
	}

	int result = munmap(bridge_map, BRIDGE_SPAN);

	if (result < 0) {
	  perror("Couldnt unmap bridge.");
	  close(fd);
	  return -4;
	}
	else{
		printf("Avalon Memory unmapped successfully\n");
	}

	close(fd);


	// Le main thread attend que le thread Gamepad
	// se termine avec pthread_join.
	printf("Press a key on the Gamepad ...\n");

	pthread_join(tid1, NULL);
	printf("Main: Union du premier thread [%lu]\n",(unsigned long)tid1);

	printf("The End ;-)\n");
	return (0);
}

