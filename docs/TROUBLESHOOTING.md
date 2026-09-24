# Troubleshooting

## Proxy says the COM port does not exist or is busy

- Check `RADIO_PORT` in `proxy_config.ini`.
- Close RS-BA1, OmniRig, WSJT-X, logging software, test scripts, or any other program using the IC-9700 COM port.
- Confirm the IC-9700 USB connection in Windows Device Manager.

## Startup stops before port 9701 / 4532 opens

V5.03 intentionally fails closed. Check `QSY-CAT_Proxy.log`.

Typical causes:

- SATELLITE mode could not be enabled or read back.
- The startup D0/D1 band-map probe did not find one 70 cm side and one 2 m side.
- A required `07 B0` MAIN/SUB exchange was not acknowledged or did not produce D0 = 70 cm / D1 = 2 m.
- D0 or D1 USB-D readback failed.
- D0/RX is outside `RX_IF_MIN_HZ .. RX_IF_MAX_HZ`.
- D1/TX is outside `TX_IF_MIN_HZ .. TX_IF_MAX_HZ`.
- A configured startup frequency did not read back exactly.

## Startup shows reversed D0/D1 bands

V5.03 checks the SAT band assignment before writing modes or frequencies.

A reversed startup state is expected to look like:

```text
INIT BAND MAP PROBE: D0/MAIN 144.xxx MHz | D1/SUB 433.xxx MHz
INIT BAND MAP: reversed assignment detected (D0=2 m, D1=70 cm). Exchanging MAIN/SUB with 07 B0.
INIT BAND MAP AFTER EXCHANGE: D0/MAIN 433.xxx MHz | D1/SUB 144.xxx MHz
INIT BAND MAP OK: MAIN/SUB exchanged; D0/MAIN is now 70 cm RX and D1/SUB is 2 m TX.
```

If the post-exchange readback still does not show 70 cm on D0 and 2 m on D1, the proxy stops before opening CAT/PTT.

## Wrong startup frequency

Check:

```ini
STARTUP_SET_FREQUENCIES=1
QO100_DL_RF_HZ=10489595000
RX_CONVERTER_LO_HZ=10056000000
RX_TX_DELTA_HZ=289500000
```

The defaults calculate:

```text
10,489.595 MHz - 10,056.000 MHz = 433.595 MHz D0/RX
433.595 MHz - 289.500 MHz       = 144.095 MHz D1/TX
```

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Test_QO100_Startup_Frequency_Config_HB0TR.ps1
```

This helper does not open the radio.

## I do not want the proxy to change frequencies at startup

Set:

```ini
STARTUP_SET_FREQUENCIES=0
```

The existing SAT frequencies are retained, but the safety windows and USB-D initialization still apply.

## VarAC frequency changes do nothing

V5.03 logs every CAT frame received from VarAC. After a slot change or manual frequency entry, check for:

```text
VARAC CAT RX: ...
VARAC CAT SET FREQ via ...
SAT SET START: ...
```

If `VARAC CAT RX` appears but `VARAC CAT SET FREQ` does not, include that raw frame in a bug report. V5.03 recognizes Icom `25 00`, `25 01`, `05`, and `00` frequency-set forms.

Check VarAC:

```text
Frequency control: CAT / Icom IC-9700
Connection:        TCP
Host:              127.0.0.1
Port:              9701
Mode:              USB-D
Diff Hz:            -10056000000
```

The log should show all five SAT QSY steps.

## D0/RX changes but D1/TX does not

Expected QSY log:

```text
SAT QSY 2/5 set D0/RX frequency (05) ... OK (FB)
SAT QSY 4/5 set D1/TX frequency (05) ... OK (FB)
```

Confirm the radio is in native SATELLITE mode and check CI-V responses for `FA` or timeout.

## PTT does not work

Check VarAC:

```text
PTT configuration: Hamlib
Host:              localhost
Port:              4532
```

Expected log:

```text
HAMLIB RX: T 1
PTT TX ON (1C 00 01) ... OK (FB)
```

PTT in V5.03 does not switch D0/D1 and does not use XCHG. `07 B0` is used only during startup if the SAT band assignment is reversed.

## I cannot hear the downlink during TX

V5.03 is designed around native IC-9700 SAT full duplex. Verify:

- SATELLITE mode is ON;
- D0 is the 433 MHz downlink/RX side;
- D1 is the 144 MHz uplink/TX side;
- both sides are USB-D;
- the converter chain and audio routing allow the 433 MHz downlink receiver to remain audible.

## Radio unexpectedly changes mode

Keep:

```ini
IGNORE_VARAC_MODE_COMMANDS=1
```

V5.03 initializes USB-D itself. VarAC command `0x26` is acknowledged locally by default rather than being forwarded to the radio.

## Frequency is not displayed in VarAC

Enable CAT frequency readback in VarAC. A configuration with `RigCatFreqRead=OFF` intentionally disables the periodic read request.

For V5.03 the recommended setting is:

```text
Read frequency: ON
Read interval:  2 seconds
```

The proxy answers `03`, `25 00`, and `25 01` read requests with the SAT D0/RX frequency.

## Proxy does not close when VarAC exits

V5.03 is hard-wired to close when the VarAC CAT socket disconnects. The log should end with messages similar to:

```text
VarAC CAT connection closed. V5.03 hard-wired behavior: stopping proxy with VarAC.
EXIT SAFETY PTT OFF (1C 00 00) ... OK (FB)
V5.03 shutdown complete: VarAC CAT disconnected; proxy is exiting.
```

The launcher closes automatically after a normal shutdown. It pauses only if PowerShell returns an error code.

## Wrong QO-100 frequency in VarAC

The tested VarAC setting is:

```text
Diff Hz = -10056000000
```

This converts downlink RF to the 433 MHz RX IF used by CAT.

`QO100_DL_RF_HZ` is the proxy's startup tuning value; it does not replace the VarAC `Diff Hz` setting.

## Port 9701 or 4532 is already in use

Change the appropriate port in `proxy_config.ini` and use the same port in VarAC. Keep the listener on `127.0.0.1` unless remote access is deliberately required and secured.

## Log file

Default:

```text
QSY-CAT_Proxy.log
```

When reporting a problem, include:

- proxy version;
- relevant log excerpt;
- sanitized `proxy_config.ini`;
- IC-9700 firmware version;
- VarAC version;
- whether the issue is startup, CAT/QSY, PTT, or full-duplex receive.
