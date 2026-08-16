# Troubleshooting

## Proxy says the COM port does not exist or is busy

- Check `RADIO_PORT` in `proxy_config.ini`.
- Close RS-BA1, OmniRig, WSJT-X, logging software, test scripts, or any other program using the IC-9700 COM port.
- Confirm the IC-9700 USB connection in Windows Device Manager.

## Startup stops before port 9701 / 4532 opens

V5.01 intentionally fails closed. Check `QSY-CAT_Proxy.log`.

Typical causes:

- SATELLITE mode could not be enabled or read back.
- D0 or D1 USB-D readback failed.
- D0/RX is outside `RX_IF_MIN_HZ .. RX_IF_MAX_HZ`.
- D1/TX is outside `TX_IF_MIN_HZ .. TX_IF_MAX_HZ`.
- A configured startup frequency did not read back exactly.

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

PTT in V5.01 does not switch D0/D1 and does not use XCHG.

## I cannot hear the downlink during TX

V5.01 is designed around native IC-9700 SAT full duplex. Verify:

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

V5.01 initializes USB-D itself. VarAC command `0x26` is acknowledged locally by default rather than being forwarded to the radio.

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
