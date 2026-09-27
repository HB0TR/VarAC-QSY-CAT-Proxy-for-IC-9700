# Changelog

All notable changes to this project will be documented in this file.

## V5.04 - 2026-09-27

### Added
- Opt-in QO-100 RF/10-Hz CAT transport (`VARAC_CAT_RF_10HZ=1`) with a matching VarAC rig section. VarAC divides the 10.489 GHz RF by 10 to fit five BCD bytes; the proxy converts back to Hz, subtracts the RX converter LO, and applies its established D0/RX and D1/TX safety windows.
- RF/10-Hz readback translates the 433 MHz IF back to the 10 GHz RF in 10 Hz units. The original IF/1-Hz behavior is the default when the new option is unset.
- Offline conversion and safety checks in GitHub Actions, in addition to PowerShell parsing and embedded C# compilation.

### Safety and compatibility
- Malformed, unsupported, out-of-window and nonrepresentable frequency requests in RF/10-Hz mode are rejected rather than forwarded to the radio.
- The legacy V5.03 CAT mode remains available unchanged.
- Field logs from VarAC 15.0.18 / IC-9700 1.50 confirmed SAT ON, D0/RX and D1/TX initialization, and correct IF readback, but showed invalid BCD for QSY with the stock 1-Hz/10-digit CAT definition and a large VarAC offset. Live validation of the new RF/10-Hz VarAC rig section is pending.

## V5.03 - 2026-09-24

### Added
- Full logging of every incoming VarAC CAT frame with `VARAC CAT RX:`.
- Broader Icom frequency-set compatibility: `25 00`, `25 01`, classic `05`, and CI-V send-frequency `00`.
- Frequency readback compatibility for `03`, `25 00`, and `25 01`.
- Fail-safe `PTT OFF` during VarAC-triggered proxy shutdown.

### Changed
- Proxy lifecycle is now hard-wired to VarAC CAT: after VarAC has connected once, closing that CAT connection stops the proxy instead of leaving it waiting for reconnection.
- The launcher exits normally after a clean VarAC-triggered shutdown and pauses only on an error.
- README now recommends VarAC CAT frequency readback ON so the current D0/RX frequency is displayed.

### Fixed
- Corrected stale V5.01 labels in the Windows batch launcher and default `proxy_config.ini`.
- Corrected stale V5.01 wording in the V5.02 documentation.
- Added explicit logging for previously silent/unhandled CAT frames, addressing the diagnostic gap seen in field testing with VarAC 15.0.18.

### Field-feedback basis
- A Windows 10 / VarAC 15.0.18 / IC-9700 firmware 1.50 report confirmed that V5.02 radio initialization and PTT worked while frequency display/QSY behavior required improved CAT compatibility and diagnostics.

## V5.02 - 2026-09-20

### Added
- Automatic SAT D0/D1 band-map probe before any startup mode or frequency writes.
- Automatic CI-V `07 B0` MAIN/SUB exchange when startup detects D0 on 2 m and D1 on 70 cm.
- Post-exchange D0/D1 frequency readback and verification before initialization continues.
- Reproducible GitHub release workflow that builds the Windows ZIP and `SHA256SUMS.txt` from the tagged source.

### Changed
- Startup no longer assumes that native SATELLITE mode always enters with 70 cm on D0 and 2 m on D1.
- Fail-closed initialization now rejects an unrecognized SAT band pair before USB-D or startup frequencies are written.
- The V5.01 native SATELLITE/full-duplex QSY and PTT model remains unchanged after the band mapping has been normalized.

### Station validation
- Confirmed on the HBØTR IC-9700 with the previously failing startup state D0/MAIN = 144 MHz and D1/SUB = 433 MHz.
- V5.02 detected the reversed assignment, exchanged MAIN/SUB with `07 B0`, verified D0 = 70 cm / D1 = 2 m, and then completed the normal USB-D and 433.595 / 144.095 MHz startup sequence.
- CAT/QSY and native SAT full-duplex PTT remained operational after the corrected initialization.

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
