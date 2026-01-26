# DE10AudioGame2
This is a continuation of the DE10AudioGame repository implementing a simon-style audio game on the DE10-Standard. 
This implementation aims to implement a Raspberry Pi Zero 2 WH sending audio samples over GPIO pins using the SPI protocol and playing those using the DE10.
The Raspberry Pi Zero 2 WH is responsible for managing audio files, packetizing audio data,
and acting as the SPI master during transmission. Audio data is streamed in structured frames to
ensure deterministic delivery and proper synchronization. On the DE10-Standard, the FPGA
fabric implements an SPI slave interface and buffering logic to receive the incoming audio
stream, while coordinating timing and data integrity for continuous playback.
