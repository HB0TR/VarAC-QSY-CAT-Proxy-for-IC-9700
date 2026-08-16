# Changelog

All notable changes to this project will be documented in this file.

## V5.01 - 2026-08-16

### Changed
- Reworked the IC-9700 control model around native **SATELLITE mode** instead of the V5.00 normal-VFO layout.
- Native SAT mapping is now `D0 = downlink/RX` and `D1 = uplink/TX`.
- PTT now uses native SAT full-duplex CI-V only: `1C 00 01` / `1C 00 00`.
- Removed the V5.00 PTT-side switching requirement; no XCHG is used.
- Startup now initializes and verifies USB-D on both SAT sides.
- QSY sets D0/RX and D1/TX independently with CI-V command `05`.
- VarAC `0x26` mode commands remain intercepted by default.

### Added
- Automatic SATELLITE ON initialization with readback.
- Fail-closed startup checks before CAT/PTT listeners open.
- Optional defined QO-100 startup frequency:
  - `STARTUP_SET_FREQUENCIES=1`
  - `QO100_DL_RF_HZ=10489595000`
  - `RX_CONVERTER_LO_HZ=10056000000`
- Automatic derivation:
  - `D0/RX IF = QO100_DL_RF_HZ - RX_CONVERTER_LO_HZ`
  - `D1/TX IF = D0/RX IF - RX_TX_DELTA_HZ`
- Exact startup frequency readback and safety-window checks.
- Non-radio helper script for validating the QO-100 startup-frequency calculation.

### Station validation
- Native SAT full-duplex PTT was confirmed with TX on the 144 MHz uplink IF while the 433 MHz downlink remained active.
- The own QO-100 downlink remained audible during TX.
- USB-D was confirmed on both D0 and D1 using `06 01 01` plus `1A 06 01 02`.
- Independent D0/D1 frequency writes and readback were confirmed at 433.595 MHz / 144.095 MHz.

## V5.00 - 2026-08-16

### Added
- Coordinated QSY for the IC-9700 QO-100 IF arrangement used by HBØTR.
- VarAC CAT/QSY endpoint on TCP `127.0.0.1:9701`.
- Separate Hamlib-compatible PTT endpoint on TCP `127.0.0.1:4532`.
- CI-V selection of MAIN for 433 MHz RX and SUB for 144 MHz TX.
- Fixed 289.500 MHz RX/TX IF delta mapping.
- Frequency readback from RX/MAIN.
- Safety windows for RX and TX IF ranges.
- Optional interception of VarAC mode command `0x26`.
- Author identification: HBØTR Stefan Franz.
- IC-9700 operating requirement: normal VFO mode with SATELLITE mode OFF.
