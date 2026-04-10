# de10-nano-space-invaders

Emulation of the Space Invaders arcade machine on the DE10-Nano FPGA board


## Instructions for installing the HPS component:
1. Using an SSH client, connect to the HPS.
2. Create the folder "/root/roms/space_ivaders/".
3. Transfer files from "HPS_src/roms/" to "/root/roms/space_invaders/" folder.
4. Transfer the file "HPS_src/SpaceInvaders_controller.cpp" into the "/root/" folder.
5. Compile with the command: g++ SpaceInvaders_controller.cpp -o SpaceInvaders_controller -lpthread
6. Then run the script: /root/SpaceInvaders_controller

(Note: Step 6 must be done after running the program on the FPGA, otherwise the memory mapping will be inaccessible, which will block the HPS.)

