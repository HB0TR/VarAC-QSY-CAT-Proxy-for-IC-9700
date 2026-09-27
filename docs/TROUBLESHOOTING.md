# Troubleshooting

## Proxy says the COM port does not exist or is busy

- Check `RADIO_PORT` in `proxy_config.ini`.
- Close RS-BA1, OmniRig, WSJT-X, logging software, test scripts, or any other program using the IC-9700 COM port.
- Confirm the IC-9700 USB connection in Windows Device Manager.

## Startup stops before port 9701 / 4532 opens

V5.04 intentionally fails closed. Check `QSY-CAT_Proxy.log`.

Typical causes:

- SATELLITE mode could not be enabled or read back.
- The startup D0/D1 band-map probe did not find one 70 cm side and one 2 m side.
- A required `07 B0` MAIN/SUB exchange was not acknowledged or did not produce D0 = 70 cm / D1 = 2 m.
- D0 or D1 USB-D readback failed.
- D0/RX is outside `RX_IF_MIN_HZ .. RX_IF_MAX_HZ`.
- D1/TX is outside `TX_IF_MIN_HZ .. TX_IF_MAX_HZ`.
- A configured startup frequency did not read back exactly.

## Startup shows reversed D0/D1 bands

V5.04 checks the SAT band assignment before writing modes or frequencies.

An occasional `INIT ERROR: SATELLITE readback missing` indicates that the IC-9700 did not answer an initial `16 5A` query. This is separate from the VarAC CAT frequency encoding. Check the COM connection and CI-V baud/address; subsequent runs can confirm SAT ON and both bands without any change to QSY handling.

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

V5.04 logs every CAT frame received from VarAC. After a slot change or manual frequency entry, check for:

```text
VARAC CAT RX: ...
VARAC CAT SET FREQ via ...
SAT SET START: ...
```

If `VARAC CAT RX` appears but `VARAC CAT SET FREQ` does not, check the logged BCD decode or RF window rejection. V5.04 recognizes Icom `25 00`, `25 01`, `05`, and `00` frequency-set forms.

For 10 GHz RF display and QSY, use the custom [RF/10-Hz VarAC CAT section](VarAC-QO100-RF10Hz-CAT.ini). Append it to the installed `VarAC_cat_commands.ini`, select its new rig name in VarAC and set:

```text
Frequency control: CAT / IC-9700 QO-100 Proxy RF 10Hz
Connection:        TCP
Host:              127.0.0.1
Port:              9701
Mode:              USB-D
Offset Hz:         0
Read frequency:    ON / 2 seconds
```

In `proxy_config.ini`, set `VARAC_CAT_RF_10HZ=1` and retain the correct `RX_CONVERTER_LO_HZ`. A 10,489.595 MHz RF request should yield 1,048,959,500 CAT units and a 433.595 MHz RX IF. The log should show all five SAT QSY steps. Keep PTT disabled while checking the first slot changes.

The stock `Icom IC-9700` CAT section has `SetFreqVfoA_param_length=10` with 1 Hz units. It cannot represent 10,489,595,000 Hz in five BCD bytes. Field logs with VarAC 15.0.18 showed values such as `25 00 B0 FB 00 FA 00`; these are not valid BCD and cannot be made safe by loosening the parser. VarAC's own Offset Hz help warns that using its offset together with frequency readback impairs operation. Use the custom RF/10-Hz profile with Offset Hz `0` instead.

## RF/10-Hz profile shows an empty VarAC frequency and sends only 2,550 Hz

The first VarAC 15.0.18 field test of V5.04's optional RF/10-Hz profile left the VarAC frequency field blank after startup, despite repeated `25 00` queries and valid 433.595 MHz radio readback. A one-slot change sent `25 00 55 02 00 00 00`, representing just 255 units (2,550 Hz) without the absolute frequency. The proxy rejected it safely. The current log does not include its outgoing reply to VarAC, so the readback failure still needs diagnosis. See [issue #2](https://github.com/HB0TR/VarAC-QSY-CAT-Proxy-for-IC-9700/issues/2). Do not use the RF/10-Hz profile as a validated QSY solution yet.

For a controlled diagnostic without transmitting, try the stock `Icom IC-9700` CAT section with `VARAC_CAT_RF_10HZ=0`, VarAC Offset Hz `0`, readback every 2 seconds, and manual entry of **433.595 MHz IF**. A valid one-slot up request should have BCD payload `50 75 59 33 04` (433,597,550 Hz) and trigger the normal five-step SAT QSY. This displays IF rather than 10 GHz RF in VarAC.

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

PTT in V5.04 does not switch D0/D1 and does not use XCHG. `07 B0` is used only during startup if the SAT band assignment is reversed.

## I cannot hear the downlink during TX

V5.04 is designed around native IC-9700 SAT full duplex. Verify:

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

V5.04 initializes USB-D itself. VarAC command `0x26` is acknowledged locally by default rather than being forwarded to the radio.

## Frequency is not displayed in VarAC

Enable CAT frequency readback in VarAC. A configuration with `RigCatFreqRead=OFF` intentionally disables the periodic read request.

For RF/10-Hz mode the recommended setting is:

```text
Read frequency: ON
Read interval:  2 seconds
```

The proxy answers `03`, `25 00`, and `25 01` read requests with QO-100 RF/10-Hz CAT units in RF mode, or the SAT D0/RX IF in legacy mode. Enabling VarAC readback with its large nonzero Offset Hz is discouraged by VarAC's own help and previously displayed the IF while QSY frames stayed malformed.

## Proxy does not close when VarAC exits

V5.04 is hard-wired to close when the VarAC CAT socket disconnects. The log should end with messages similar to:

```text
VarAC CAT connection closed. V5.04 hard-wired behavior: stopping proxy with VarAC.
EXIT SAFETY PTT OFF (1C 00 00) ... OK (FB)
V5.04 shutdown complete: VarAC CAT disconnected; proxy is exiting.
```

The launcher closes automatically after a normal shutdown. It pauses only if PowerShell returns an error code.

## Wrong QO-100 frequency in VarAC

For RF/10-Hz mode use:

```text
Offset Hz = 0
VARAC_CAT_RF_10HZ=1
RX_CONVERTER_LO_HZ=10056000000
```

The proxy converts the downlink RF to its 433 MHz RX IF. `FrequencyOffsetHZ=-10056000000` stored in VarAC.INI does not make the stock five-byte, 1-Hz BCD frequency format represent an 11-digit RF frequency.

`QO100_DL_RF_HZ` is the proxy's independent startup tuning value.

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
