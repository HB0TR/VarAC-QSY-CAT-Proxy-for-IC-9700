# Architecture

## Purpose

VarAC presents one receive/downlink frequency to CAT. In the HBØTR QO-100 station, the IC-9700 must maintain two coordinated IF frequencies while operating full duplex:

- SAT `D0`: 433 MHz downlink / RX IF
- SAT `D1`: 144 MHz uplink / TX IF

V5.01 uses the IC-9700's native **SATELLITE mode**.

## Interfaces

### CAT / QSY server
- TCP: `127.0.0.1:9701`
- Client: VarAC direct CAT
- Expected rig profile: Icom IC-9700

The proxy recognizes the Icom CI-V frequency-set forms used by VarAC (`25 00` and classic `05`). A frequency inside the configured RX IF window is treated as D0/RX and the D1/TX IF is derived with the configured delta.

### PTT server
- TCP: `127.0.0.1:4532`
- Client: VarAC Hamlib PTT
- Supported PTT: `T 1`, `T 0`, plus compatible long-form rigctld command names handled by the proxy

### Radio interface
- Serial port from `proxy_config.ini`
- Default: `COM5`, 115200 baud, 8N1
- CI-V address: `A2h`
- DTR HIGH, RTS HIGH

## Startup sequence

V5.01 opens the physical radio first and does not open CAT/PTT listeners until initialization succeeds.

1. Read SATELLITE status: `16 5A`.
2. If needed, enable SATELLITE: `16 5A 01`; verify readback.
3. Select D0/RX: `07 D0`.
4. Set D0/RX USB-D:
   - `06 01 01`
   - `1A 06 01 02`
   - verify with `04` and `1A 06`.
5. If startup frequency setting is enabled, set and read back D0/RX.
6. Select D1/TX: `07 D1`.
7. Set D1/TX USB-D and verify.
8. If startup frequency setting is enabled, set and read back D1/TX.
9. Return to D0/RX and verify D0/RX again.
10. Verify SATELLITE remains ON.
11. Start TCP listeners.

Any failed mandatory step prevents CAT/PTT from opening.

## Startup RF-to-IF calculation

With `STARTUP_SET_FREQUENCIES=1`:

```text
D0_RX_IF = QO100_DL_RF_HZ - RX_CONVERTER_LO_HZ
D1_TX_IF = D0_RX_IF - RX_TX_DELTA_HZ
```

Default station values:

```text
10,489.595 MHz - 10,056.000 MHz = 433.595 MHz
433.595 MHz - 289.500 MHz       = 144.095 MHz
```

## QSY sequence

For a new VarAC RX IF:

1. `07 D0` — select D0/RX.
2. `05 ...` — set D0/RX.
3. `07 D1` — select D1/TX.
4. `05 ...` — set `RX_IF - RX_TX_DELTA_HZ`.
5. `07 D0` — return to D0/RX.

D0 and D1 writes were operationally tested as independent in native SAT mode.

## PTT sequence

Native SAT full-duplex:

```text
TX ON:  1C 00 01
TX OFF: 1C 00 00
```

No D0/D1 selection and no XCHG are performed for PTT.

## Frequency readback

VarAC frequency readback represents the downlink/RX IF. The proxy selects D0 and returns its frequency.

## Mode-command handling

When `IGNORE_VARAC_MODE_COMMANDS=1`, VarAC CI-V command `0x26` is acknowledged locally instead of being forwarded.

The proxy owns radio-mode initialization and uses the tested USB-D sequence `06 01 01` + `1A 06 01 02`.

## Safety windows

Default:

```text
D0/RX: 433000000 .. 434000000 Hz
D1/TX: 144000000 .. 146000000 Hz
```

PTT is rejected if the cached D1/TX frequency is outside the TX safety window.

## No virtual COM ports

The proxy uses TCP on the VarAC side and owns the physical IC-9700 COM port itself.
