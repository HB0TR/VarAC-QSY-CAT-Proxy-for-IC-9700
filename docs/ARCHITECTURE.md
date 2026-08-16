# Architecture

## Purpose

VarAC normally emits a single CAT frequency. In the HBØTR QO-100 station, the IC-9700 must be kept on two coordinated intermediate frequencies:

- MAIN: 433 MHz receive IF
- SUB: 144 MHz transmit IF

V5.00 bridges that mismatch while the IC-9700 remains in **normal VFO mode; SATELLITE mode must be OFF**.

## Interfaces

### CAT / QSY server
- TCP: `127.0.0.1:9701`
- Client: VarAC direct CAT control
- Expected rig profile: Icom IC-9700

The proxy understands the Icom CI-V frequency-set forms used by VarAC (`25 00` and classic `05`). For frequencies inside the configured 433 MHz RX window, it calculates the matching TX IF and sends separate commands to the physical IC-9700.

### PTT server
- TCP: `127.0.0.1:4532`
- Client: VarAC Hamlib PTT
- Supported PTT commands: `T 1`, `T 0`, plus equivalent long-form rigctld command names handled by the proxy

### Radio interface
- Serial COM port configured in `proxy_config.ini`
- Default: `COM5`, 115200 baud, 8N1
- CI-V address: A2h

## QSY sequence

For a new RX IF frequency, V5.00 performs:

1. Select MAIN: CI-V `07 D0`
2. Set MAIN RX frequency: CI-V `05 ...`
3. Select SUB: CI-V `07 D1`
4. Set SUB TX frequency: CI-V `05 ...`
5. Select MAIN again: CI-V `07 D0`

The proxy only applies the two-frequency mapping inside the configured RX window. Other CAT frames are forwarded unchanged unless explicitly intercepted.

## PTT sequence

### TX ON
1. Select SUB/TX (`07 D1`)
2. PTT ON (`1C 00 01`)

### TX OFF
1. PTT OFF (`1C 00 00`)
2. Select MAIN/RX (`07 D0`)

## Frequency mapping

```text
TX_IF_Hz = RX_IF_Hz - RX_TX_DELTA_HZ
```

Default:

```text
RX_TX_DELTA_HZ = 289500000
```

Example:

```text
433595000 - 289500000 = 144095000
```

## Mode-command handling

When `IGNORE_VARAC_MODE_COMMANDS=1`, VarAC CI-V command `0x26` is acknowledged locally instead of being forwarded to the transceiver. This was introduced because direct mode switching during development produced unwanted TX behavior. The intended radio configuration is **normal VFO mode with SATELLITE mode OFF**, with USB-D set manually on the IC-9700.

## No virtual COM ports

The proxy uses TCP on the VarAC side and owns the physical IC-9700 COM port itself. This avoids the COM-port sharing problem that occurred in early development versions.
