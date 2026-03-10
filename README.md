# DE10AudioGame2
This project extends prior audio output work on Intel's SoC FPGA platform by implementing a distributed interactive control system between an Adafruit ItsyBitsy 5V 32u4 microcontroller and the DE10-Standard board. In this design, user input is captured via push buttons connected to the ItsyBitsy and transmitted over a UART interface to the DE10-Standard, where button press commands trigger audio playback sequences through the onboard WM8731 audio codec. The system demonstrates reliable, real-time command communication across heterogeneous platforms and emphasizes hardware–software co-design.


# Component Diagram
<img width="975" height="569" alt="image" src="https://github.com/user-attachments/assets/4a156a19-9ea9-4b33-86ee-cb44a2d4d8a5" />
