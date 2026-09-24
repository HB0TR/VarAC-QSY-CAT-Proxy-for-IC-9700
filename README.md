# VarAC QSY-CAT Proxy for IC-9700 by HBØTR V5.03

A Windows CAT/PTT proxy for **VarAC + VARA SAT + Icom IC-9700** in a QO-100 transverter setup. V5.03 keeps the native SATELLITE/full-duplex and automatic D0/D1 band-map logic from V5.02, adds broader VarAC/Icom CAT frequency compatibility and exits automatically when VarAC closes its CAT connection.

**Author:** HBØTR Stefan Franz  
**QRZ:** https://www.qrz.com/db/HB0TR  
**Version:** V5.03

> This is an independent amateur-radio project. It is not affiliated with or endorsed by VarAC, Icom, Kuhne electronic, or the VARA software author.

## What's new in V5.03

V5.03 is a compatibility and lifecycle release based on field feedback from a Windows 10 / VarAC 15.0.18 / IC-9700 1.50 station.

### CAT/QSY compatibility

The proxy now logs every incoming VarAC CAT frame and recognizes these Icom frequency-set forms:

- `25 00 + 5-byte BCD`
- `25 01 + 5-byte BCD`
- classic `05 + 5-byte BCD`
- CI-V send-frequency `00 + 5-byte BCD`

Recognized frequency changes inside the configured 433 MHz RX window are converted into the tested native SAT sequence that sets D0/RX and D1/TX together. Unknown CAT frames are logged before passthrough, making future VarAC rig-definition differences visible in `QSY-CAT_Proxy.log`.

Frequency readback supports `03` plus `25 00` / `25 01` query forms and always reports the SAT D0/RX frequency to VarAC.

### VarAC-coupled shutdown

V5.03 is intentionally hard-wired to exit after VarAC closes the CAT connection. There is no INI switch for this behavior.

On CAT disconnect the proxy:

1. closes the VarAC CAT socket;
2. sends a fail-safe native SAT `PTT OFF` (`1C 00 00`);
3. stops the proxy loop;
4. closes CAT/PTT listeners and the IC-9700 serial port;
5. allows the launcher window to close normally.

The batch launcher pauses only after an error; a normal VarAC-triggered shutdown closes without waiting for a keypress.

### Existing V5.02 SAT initialization retained

Before changing mode or frequency, the proxy still probes SAT D0/D1. If D0 is 2 m and D1 is 70 cm, it exchanges MAIN/SUB once with `07 B0`, reads both sides again, and continues only when D0 is the 70 cm RX side and D1 is the 2 m TX side.

## Data flow

```text
VarAC QO-100 downlink frequency
        |
        | Diff Hz = -10056000000
        v
433 MHz RX IF presented to CAT
        |
        v
+------------------------------------------------+
| VarAC QSY-CAT Proxy V5.03                     |
|                                                |
| CAT/QSY: TCP 127.0.0.1:9701                   |
| PTT:     Hamlib-compatible TCP 127.0.0.1:4532 |
|                                                |
| SAT D0 / RX = requested 433 MHz IF             |
| SAT D1 / TX = D0 - 289.500 MHz                 |
| PTT = native CI-V 1C 00 01 / 1C 00 00         |
+------------------------------------------------+
        |
        v
COM5 / 115200 / CI-V A2h
        |
        v
Icom IC-9700 in SATELLITE mode
        |
        +--> D0: 433 MHz downlink receive
        |
        +--> D1: 144 MHz uplink transmit
             while D0 remains active
```

## Tested full-duplex behavior

The native SAT full-duplex design used by V5.03 was validated on the HBØTR IC-9700 station with these behaviors:

- `16 5A 01` enables native SATELLITE mode.
- `07 D0` addresses the 433 MHz downlink/RX SAT side.
- `07 D1` addresses the 144 MHz uplink/TX SAT side.
- V5.03 probes D0/D1 before initialization and uses `07 B0` only when the two SAT bands are reversed.
- Both SAT sides can be set to USB-D with:
  - `06 01 01` — USB
  - `1A 06 01 02` — DATA ON / filter 2
- CI-V command `05` sets the D0 and D1 frequencies independently.
- PTT uses only `1C 00 01` / `1C 00 00`.
- During TX on 144 MHz, the 433 MHz downlink remained active and the own QO-100 downlink was audible.

## Requirements

- Windows 10 or Windows 11
- VarAC with VARA SAT
- Icom IC-9700 connected by USB and visible as a Windows COM port
- IC-9700 CI-V address `A2h`
- USB CI-V at 115200 baud
- QO-100 converter chain using approximately 433 MHz RX IF and 144 MHz TX IF
- Local TCP port `9701` for CAT/QSY
- Local TCP port `4532` for Hamlib-compatible PTT

No virtual COM-port pair is required.

## Quick start

1. Download or clone the repository.
2. Edit `proxy_config.ini` if the IC-9700 is not on `COM5`.
3. Review the converter values and `QO100_DL_RF_HZ` in `proxy_config.ini`.
4. Start `Start_VarAC_QSY-CAT_Proxy.bat`.
5. The proxy opens the radio, enables SATELLITE mode if needed, probes the D0/D1 band assignment, exchanges MAIN/SUB with `07 B0` if the 2 m / 70 cm sides are reversed, initializes both SAT sides to USB-D, optionally applies the configured startup frequencies, and verifies the resulting state.
6. Only after successful initialization are CAT port `9701` and PTT port `4532` opened.
7. Start VarAC / VARA SAT.
8. Enable VarAC CAT frequency readback so the displayed frequency follows D0/RX.
9. For the first transmit test, use minimum safe drive power and verify the complete converter chain.

When VarAC later closes its CAT connection, V5.03 shuts itself down automatically.

## VarAC configuration

### Application Launcher

Use **VARA SAT** as the modem application.

<a href="docs/images/application-launcher.jpg"><img src="docs/images/application-launcher.jpg" alt="VarAC Application Launcher configuration" width="100%"></a>

### Frequency control

```text
Frequency control: CAT
Rig:               Icom IC-9700
CAT connection:    TCP
Host:              127.0.0.1
Port:              9701
Mode:              USB-D
Diff Hz:            -10056000000
Read frequency:    ON
```

The VarAC `Diff Hz` converts QO-100 downlink RF to the IC-9700 RX IF:

```text
10,489.595 MHz - 10,056.000 MHz = 433.595 MHz
```

`QO100_DL_RF_HZ` in `proxy_config.ini` is a separate setting: it defines the **startup QO-100 downlink frequency** used by the proxy before VarAC connects.

### PTT control

```text
PTT configuration: Hamlib
Host:              localhost
Port:              4532
```

The proxy accepts the Hamlib-style `T 1` / `T 0` PTT commands.

<a href="docs/images/varac-rig-control.jpg"><img src="docs/images/varac-rig-control.jpg" alt="VarAC RIG Control configuration for the IC-9700 proxy" width="100%"></a>

## IC-9700 operation in V5.03

V5.03 is designed for **native SATELLITE mode**.

```text
SATELLITE mode:        ON
D0 / Downlink / RX:    433 MHz IF, USB-D
D1 / Uplink / TX:      144 MHz IF, USB-D
CI-V address:          A2h
USB CI-V baud rate:    115200
```

The proxy initializes SATELLITE mode and USB-D automatically. It opens the serial port with:

```text
Data:      8N1
Handshake: none
DTR:       HIGH
RTS:       HIGH
```

## Proxy configuration

Default `proxy_config.ini`:

```ini
LISTEN_HOST=127.0.0.1
LISTEN_PORT=9701

HAMLIB_HOST=127.0.0.1
HAMLIB_PORT=4532

RADIO_PORT=COM5
BAUD=115200
CIV_ADDRESS=A2

RX_TX_DELTA_HZ=289500000

STARTUP_SET_FREQUENCIES=1
QO100_DL_RF_HZ=10489595000
RX_CONVERTER_LO_HZ=10056000000

RX_IF_MIN_HZ=433000000
RX_IF_MAX_HZ=434000000
TX_IF_MIN_HZ=144000000
TX_IF_MAX_HZ=146000000

IGNORE_VARAC_MODE_COMMANDS=1
LOG_FILE=QSY-CAT_Proxy.log
```

### Startup frequency calculation

When:

```ini
STARTUP_SET_FREQUENCIES=1
```

the proxy calculates:

```text
D0/RX IF = QO100_DL_RF_HZ - RX_CONVERTER_LO_HZ
D1/TX IF = D0/RX IF - RX_TX_DELTA_HZ
```

With the defaults:

```text
QO100_DL_RF_HZ      = 10,489.595 MHz
RX_CONVERTER_LO_HZ  = 10,056.000 MHz
D0/RX IF             =    433.595 MHz
RX_TX_DELTA_HZ       =    289.500 MHz
D1/TX IF             =    144.095 MHz
```

The RF value is stored as **integer Hz** (`10489595000`) to avoid decimal-separator ambiguity.

Set:

```ini
STARTUP_SET_FREQUENCIES=0
```

to retain the IC-9700's existing SAT frequencies at startup. Safety-window and USB-D checks still apply.

The helper `tools/Test_QO100_Startup_Frequency_Config_HB0TR.ps1` validates the INI calculation without opening the COM port or changing the radio.

## QSY sequence

For each VarAC QSY inside the configured 433 MHz RX window, V5.03 performs:

```text
07 D0       select SAT D0/RX
05 ...      set requested RX IF
07 D1       select SAT D1/TX
05 ...      set RX IF - 289.500 MHz
07 D0       return selection to D0/RX
```

The D0 and D1 frequency writes were tested independently in SATELLITE mode; setting one side did not move the other side.

### VarAC CAT commands accepted by V5.03

For maximum compatibility, V5.03 accepts modern and classic Icom frequency commands from VarAC:

```text
25 00 <5 BCD bytes>   set VFO/frequency
25 01 <5 BCD bytes>   alternate VFO selector
05    <5 BCD bytes>   classic set-frequency
00    <5 BCD bytes>   CI-V send-frequency form
03                    read current D0/RX frequency
25 00                 read VFO/frequency
25 01                 alternate read selector
```

Every incoming CAT frame is logged with `VARAC CAT RX:`. A recognized QSY is additionally logged as `VARAC CAT SET FREQ ...` before the normal five-step SAT QSY sequence.


## PTT sequence

Native SAT full-duplex PTT is intentionally simple:

```text
PTT ON:   1C 00 01
PTT OFF:  1C 00 00
```

No `07 D0/D1` selection and no `07 B0` XCHG are used for PTT.

## USB-D initialization and VarAC mode commands

V5.03 initializes both SAT sides to USB-D using the tested classic CI-V sequence:

```text
06 01 01
1A 06 01 02
```

The proxy then verifies USB and DATA ON by readback.

Keep:

```ini
IGNORE_VARAC_MODE_COMMANDS=1
```

VarAC Icom mode command `0x26` is acknowledged locally rather than forwarded to the radio. This keeps the verified USB-D state intact and avoids relying on `0x26` in IC-9700 SATELLITE mode.

## Startup safety / fail-closed behavior

Before opening CAT/PTT listeners, V5.03 verifies:

- SATELLITE mode is ON;
- D0/D1 contain the expected 70 cm / 2 m band pair, with automatic `07 B0` correction if initially reversed;
- D0/RX is USB-D;
- D1/TX is USB-D;
- D0/RX lies inside the configured RX IF safety window;
- D1/TX lies inside the configured TX IF safety window;
- when startup frequency setting is enabled, the requested values read back exactly;
- D0/RX is checked again after D1/TX is written.

If initialization fails, CAT/PTT listeners are not started.

## Expected log output

A successful startup with the default QO-100 frequency includes lines similar to:

```text
INIT OK: SATELLITE = ON
INIT BAND MAP PROBE: D0/MAIN 433.595000 MHz | D1/SUB 144.095000 MHz
INIT BAND MAP OK: D0/MAIN is 70 cm RX and D1/SUB is 2 m TX; no exchange required.
INIT START FREQUENCIES: ON | D0/RX 433.595000 MHz | D1/TX 144.095000 MHz
INIT OK: D0/RX = USB-D
INIT OK: D0/RX = 433.595000 MHz
INIT OK: D1/TX = USB-D
INIT OK: D1/TX = 144.095000 MHz
RADIO INIT COMPLETE: SATELLITE ON | D0/RX 433.595000 MHz USB-D | D1/TX 144.095000 MHz USB-D | D0 selected.
```

A successful QSY looks similar to:

```text
SAT QSY 1/5 select D0/RX (07 D0) ... OK (FB)
SAT QSY 2/5 set D0/RX frequency (05) ... OK (FB)
SAT QSY 3/5 select D1/TX (07 D1) ... OK (FB)
SAT QSY 4/5 set D1/TX frequency (05) ... OK (FB)
SAT QSY 5/5 select D0/RX again (07 D0) ... OK (FB)
FREQ: SAT D0/RX 433.595000 MHz | SAT D1/TX 144.095000 MHz
```

A successful PTT cycle looks similar to:

```text
HAMLIB RX: T 1
PTT TX ON (1C 00 01) ... OK (FB)
PTT = TX | native SAT full-duplex active.

HAMLIB RX: T 0
PTT TX OFF (1C 00 00) ... OK (FB)
PTT = RX | D0/downlink remains the receive side.
```

## Upgrade from V5.02

V5.03 keeps the V5.02 SAT band-map and native full-duplex radio model. No additional INI parameter is required.

Changes to be aware of:

- CAT frequency input accepts additional Icom command forms and is fully logged.
- VarAC frequency readback should be enabled if you want the current frequency displayed.
- The proxy now exits automatically when the VarAC CAT connection closes.
- The launcher and configuration headers now correctly identify V5.03.

Users upgrading directly from V5.00 or V5.01 should also review the native SATELLITE-mode configuration described above.

## Safety

The proxy controls real radio hardware and can key the transmitter.

Before the first transmit test:

- reduce IC-9700 drive power to a safe level for the upconverter;
- verify the 144 MHz TX IF and converter input-power requirements;
- verify the 433 MHz downlink remains correctly mapped;
- use a dummy load or suitable test arrangement where appropriate;
- confirm PTT OFF reliably returns the transmitter to receive state;
- comply with local amateur-radio regulations and RF-safety requirements.

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

The proxy writes `QSY-CAT_Proxy.log` next to the script. This file is intentionally ignored by Git.

## Project files

```text
.
├── VarAC_QSY-CAT_Proxy_IC-9700_HB0TR.ps1
├── Start_VarAC_QSY-CAT_Proxy.bat
├── proxy_config.ini
├── README.md
├── CHANGELOG.md
├── LICENSE
├── NOTICE
├── CITATION.cff
├── CONTRIBUTING.md
├── SECURITY.md
├── tools/
│   └── Test_QO100_Startup_Frequency_Config_HB0TR.ps1
├── docs/
│   ├── ARCHITECTURE.md
│   ├── TROUBLESHOOTING.md
│   ├── LICENSE-OPTIONS.md
│   └── images/
└── .github/
```

## License

MIT License. See `LICENSE`.

## Author

**HBØTR Stefan Franz**  
https://www.qrz.com/db/HB0TR

## References

- VarAC: https://www.varac-hamradio.com/
- VarAC CAT customization guide: https://www.varac-hamradio.com/post/rig-control-cat-command-file-cat-customization-guide
- Icom IC-9700 CI-V Reference Guide: https://www.icomjapan.com/support/manual/2161/
- Icom IC-9700 product page: https://www.icomjapan.com/lineup/products/IC-9700/
- Kuhne electronic: https://www.kuhne-electronic.com/

## Disclaimer

Amateur-radio operation is subject to your local regulations and station licence. You are responsible for RF safety, frequency accuracy, drive levels, occupied bandwidth, and lawful operation. This software is supplied without warranty; test it carefully with your own station before relying on it.
