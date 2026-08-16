# Security and safety

This project controls a radio transmitter. Treat unexpected behavior as a station-safety issue as well as a software bug.

## Network exposure

The default CAT and PTT listeners bind to `127.0.0.1` only. This is intentional. Do not bind the proxy to a LAN/WAN address unless you understand the consequences and provide appropriate host/network security.

## Reporting

For ordinary bugs, use a GitHub issue once the repository is published. For a problem that could cause unintended keying, unsafe frequency selection, or remote control exposure, avoid public proof-of-concept details until the author has had a chance to review the report.

Author: HBØTR Stefan Franz  
https://www.qrz.com/db/HB0TR
