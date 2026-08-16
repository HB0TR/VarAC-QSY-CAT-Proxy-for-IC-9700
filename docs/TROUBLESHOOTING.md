# Troubleshooting

## Proxy says the COM port does not exist or is busy

- Check `RADIO_PORT` in `proxy_config.ini`.
- Close RS-BA1, OmniRig, WSJT-X, logging software, or any other program that may have opened the IC-9700 COM port.
- Confirm the IC-9700 USB connection is present in Windows Device Manager.

## VarAC frequency changes do nothing

Check the VarAC frequency-control path:

```text
Frequency control: CAT / Icom IC-9700
Connection:        TCP
Host:              127.0.0.1
Port:              9701
Mode:              USB-D
Diff Hz:            -10056000000
```

Then check the proxy log for `VarAC CAT connected.` and for the five `SET` steps.

## RX changes but TX does not

V5.00 is specifically intended to set both sides. The log should contain:

```text
2/5 set RX frequency on MAIN (05) ... OK (FB)
4/5 set TX frequency on SUB (05) ... OK (FB)
```

If step 4 fails, verify that the IC-9700 is in **normal VFO mode with SATELLITE mode OFF** and that the 144 MHz SUB side is available.

## Frequency control works but PTT does not

Check the VarAC PTT path:

```text
PTT configuration: Hamlib
Host:              localhost
Port:              4532
```

The proxy should log `VarAC Hamlib/PTT connected.` followed by `HAMLIB RX: T 1` or `HAMLIB RX: T 0`.

## PTT works but QSY does not

PTT and frequency control use separate local TCP ports. Confirm that VarAC CAT is connected to **9701**, not 4532.

## Radio unexpectedly switches mode or transmits during QSY

Keep:

```ini
IGNORE_VARAC_MODE_COMMANDS=1
```

Keep the IC-9700 in **VFO mode with SATELLITE mode OFF** and set USB-D manually before starting operation. Do not change this option until the behavior has been tested safely with your station.

## Wrong QO-100 frequency

For the tested Kuhne RX chain:

```text
QO-100 downlink RF 10,489.595 MHz
- LNC LO          10,056.000 MHz
= IC-9700 RX IF      433.595 MHz
```

VarAC therefore uses:

```text
Diff Hz = -10056000000
```

For TX, V5.00 derives:

```text
433.595 MHz - 289.500 MHz = 144.095 MHz
```

The Kuhne 144 MHz IF upconverter then produces the corresponding 2.4 GHz uplink frequency.

## Port 9701 or 4532 is already in use

Change the appropriate port in `proxy_config.ini` and use the same value in VarAC. Keep both endpoints on loopback (`127.0.0.1`) unless you deliberately understand and secure remote access.

## Log file

The log is written to:

```text
QSY-CAT_Proxy.log
```

When reporting a bug, include:

- proxy version;
- relevant log excerpt;
- `proxy_config.ini` with any private/local details removed if desired;
- IC-9700 firmware version;
- VarAC version;
- whether the problem is CAT/QSY, PTT, or both.

Do not post unrelated personal data or credentials.
