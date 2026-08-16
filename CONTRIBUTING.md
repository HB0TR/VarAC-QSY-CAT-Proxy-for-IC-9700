# Contributing

Contributions are welcome, especially from operators who can test with an IC-9700 and QO-100 hardware.

## Before opening a pull request

1. Describe the station configuration and the reason for the change.
2. Keep changes focused and avoid unrelated formatting churn.
3. Do not change the default safety windows without explaining the hardware use case.
4. Preserve the author/copyright and licence notices.
5. Never commit real log files containing information you do not want public.

## Bug reports

Please include:

- VarAC QSY-CAT Proxy version;
- VarAC version;
- Windows version;
- IC-9700 firmware version;
- relevant lines from `QSY-CAT_Proxy.log`;
- whether CAT/QSY, PTT, or both are affected;
- your RX IF, TX IF, and converter LO arrangement if it differs from the HBØTR setup.

## Code style

V5.00 is a PowerShell launcher containing an embedded C# implementation. Prefer clear comments and conservative changes because the software controls live RF hardware.
