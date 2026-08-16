# Changelog

All notable changes to this project will be documented in this file.

## V5.00 - 2026-08-16

### Added
- Coordinated QSY for the IC-9700 QO-100 IF arrangement used by HBØTR.
- VarAC CAT/QSY endpoint on TCP `127.0.0.1:9701`.
- Separate Hamlib-compatible PTT endpoint on TCP `127.0.0.1:4532`.
- CI-V selection of MAIN for 433 MHz RX and SUB for 144 MHz TX.
- Fixed 289.500 MHz RX/TX IF delta mapping.
- Frequency readback from RX/MAIN.
- Safety windows for RX and TX IF ranges.
- Optional interception of VarAC mode command `0x26` to avoid unwanted mode-switching/transmit behavior.
- English console output and documentation.
- Author identification: HBØTR Stefan Franz.
- IC-9700 operating requirement: normal VFO mode with SATELLITE mode OFF.

### Tested station mapping
- RX/MAIN: 433.595 MHz USB-D.
- TX/SUB: 144.095 MHz USB-D.
- IC-9700 CI-V address: A2h.
- Serial: 115200 baud, 8N1, DTR HIGH, RTS HIGH.
