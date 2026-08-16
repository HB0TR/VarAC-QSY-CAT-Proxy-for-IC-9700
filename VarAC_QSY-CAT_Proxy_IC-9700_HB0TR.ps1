# VarAC QSY-CAT Proxy for IC-9700 by HBØTR V5.01
# Author: HBØTR Stefan Franz | https://www.qrz.com/db/HB0TR
# Copyright (c) 2026 Stefan Franz, HBØTR
# SPDX-License-Identifier: MIT
#
# See README.md for setup, safety notes, and supported IF mapping.

param(
    [string]$ConfigPath = "$PSScriptRoot\proxy_config.ini"
)

$ErrorActionPreference = 'Stop'

function Read-SimpleIni([string]$Path) {
    $cfg = @{}
    if (-not (Test-Path -LiteralPath $Path)) { throw "Configuration file not found: $Path" }
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        $p = $line.IndexOf('=')
        if ($p -lt 1) { continue }
        $cfg[$line.Substring(0,$p).Trim()] = $line.Substring($p+1).Trim()
    }
    return $cfg
}
function Get-Cfg([hashtable]$Cfg,[string]$Key,[string]$Default) {
    if ($Cfg.ContainsKey($Key) -and $Cfg[$Key] -ne '') { return [string]$Cfg[$Key] }
    return $Default
}

$cfg       = Read-SimpleIni $ConfigPath
$listenHost= Get-Cfg $cfg 'LISTEN_HOST' '127.0.0.1'
$listenPort= [int](Get-Cfg $cfg 'LISTEN_PORT' '9701')
$hamHost   = Get-Cfg $cfg 'HAMLIB_HOST' '127.0.0.1'
$hamPort   = [int](Get-Cfg $cfg 'HAMLIB_PORT' '4532')
$radioPort = Get-Cfg $cfg 'RADIO_PORT' 'COM5'
$baud      = [int](Get-Cfg $cfg 'BAUD' '115200')
$civText   = (Get-Cfg $cfg 'CIV_ADDRESS' 'A2').Replace('0x','').Replace('h','')
$civAddr   = [Convert]::ToByte($civText,16)
$rxTxDelta = [Int64](Get-Cfg $cfg 'RX_TX_DELTA_HZ' '289500000')
$rxMin     = [Int64](Get-Cfg $cfg 'RX_IF_MIN_HZ' '433000000')
$rxMax     = [Int64](Get-Cfg $cfg 'RX_IF_MAX_HZ' '434000000')
$txMin     = [Int64](Get-Cfg $cfg 'TX_IF_MIN_HZ' '144000000')
$txMax     = [Int64](Get-Cfg $cfg 'TX_IF_MAX_HZ' '146000000')
$startupSetFreq = ((Get-Cfg $cfg 'STARTUP_SET_FREQUENCIES' '1') -ne '0')

# Human/station-level startup setting: actual QO-100 downlink RF frequency.
# Use integer Hz in the INI to avoid locale-dependent decimal parsing.
$qo100DlRfHz    = [Int64](Get-Cfg $cfg 'QO100_DL_RF_HZ' '10489595000')
$rxConverterLoHz = [Int64](Get-Cfg $cfg 'RX_CONVERTER_LO_HZ' '10056000000')

# Derive the IC-9700 IFs from the QO-100 RF frequency.
$startupRxHz    = $qo100DlRfHz - $rxConverterLoHz
$startupTxHz    = $startupRxHz - $rxTxDelta

$ignoreMode= ((Get-Cfg $cfg 'IGNORE_VARAC_MODE_COMMANDS' '1') -ne '0')
$logPath   = Join-Path $PSScriptRoot (Get-Cfg $cfg 'LOG_FILE' 'QSY-CAT_Proxy.log')

$source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Ports;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace QO100CatProxyV501
{
    public sealed class Proxy : IDisposable
    {
        private readonly TcpListener listener;
        private readonly TcpListener hamListener;
        private TcpClient client;
        private NetworkStream app;
        private TcpClient hamClient;
        private NetworkStream hamStream;
        private readonly SerialPort radio;
        private readonly byte civ;
        private readonly long delta, rxMin, rxMax, txMin, txMax;
        private readonly bool startupSetFreq;
        private readonly long startupRxHz, startupTxHz;
        private readonly bool ignoreMode;
        private readonly string logFile;
        private readonly List<byte> appBuffer = new List<byte>();
        private readonly StringBuilder hamBuffer = new StringBuilder();
        private long lastRxHz = -1;
        private bool pttState = false;
        private long lastTxHz = -1;

        public Proxy(string host, int port, string hamHost, int hamPort, string radioPort, int baud, byte civAddress,
                     long deltaHz, long rxIfMinHz, long rxIfMaxHz, long txIfMinHz, long txIfMaxHz,
                     bool startupSetFrequencies, long startupRxFrequencyHz, long startupTxFrequencyHz,
                     bool ignoreModeCommands, string logPath)
        {
            listener = new TcpListener(IPAddress.Parse(host), port);
            hamListener = new TcpListener(IPAddress.Parse(hamHost), hamPort);
            civ = civAddress; delta = deltaHz; rxMin = rxIfMinHz; rxMax = rxIfMaxHz;
            txMin = txIfMinHz; txMax = txIfMaxHz;
            startupSetFreq = startupSetFrequencies;
            startupRxHz = startupRxFrequencyHz;
            startupTxHz = startupTxFrequencyHz;
            ignoreMode = ignoreModeCommands; logFile = logPath;
            radio = new SerialPort(radioPort, baud, Parity.None, 8, StopBits.One);
            radio.Handshake = Handshake.None;
            // Matches DTR=H / RTS=H from the working direct CAT test.
            radio.DtrEnable = true;
            radio.RtsEnable = true;
            radio.ReadTimeout = 30;
            radio.WriteTimeout = 1000;
            radio.ReadBufferSize = 16384;
            radio.WriteBufferSize = 4096;
        }

        public void Run()
        {
            Log("=== VarAC QSY-CAT Proxy for IC-9700 by HBØTR V5.01 started ===");
            Log("Author HBØTR Stefan Franz | https://www.qrz.com/db/HB0TR");
            Log("RADIO INIT: native SATELLITE FULL-DUPLEX; QO-100 DL RF -> RX IF -> TX IF startup calculation; SAT ON; USB-D.");
            Log("PTT MODE: native SAT PTT only (1C 00 01 / 1C 00 00); no XCHG.");
            Log(String.Format("CAT/Frequency: {0} | Hamlib/PTT: {1} | Radio: {2} | {3} baud | CI-V {4:X2}h",
                ((IPEndPoint)listener.LocalEndpoint), ((IPEndPoint)hamListener.LocalEndpoint), radio.PortName, radio.BaudRate, civ));

            radio.Open();
            Log("COM port to the IC-9700 is open.");

            // Fail closed: VarAC CAT and Hamlib/PTT listeners are started only
            // after the radio initialization has been acknowledged and verified.
            if (!InitializeRadio())
            {
                Log("SAFETY STOP: radio initialization failed. CAT/PTT listeners were NOT started.");
                throw new InvalidOperationException("IC-9700 startup initialization failed.");
            }

            listener.Start();
            hamListener.Start();
            Log("RADIO READY: SATELLITE ON | D0/RX USB-D | D1/TX USB-D | native FULL-DUPLEX | D0 selected.");
            Log("Waiting for VarAC CAT and Hamlib/PTT connections ...");

            while (true)
            {
                try
                {
                    if (client == null && listener.Pending())
                    {
                        client = listener.AcceptTcpClient();
                        client.NoDelay = true;
                        app = client.GetStream();
                        app.ReadTimeout = 50;
                        app.WriteTimeout = 1000;
                        appBuffer.Clear();
                        Log("VarAC CAT connected.");
                    }

                    if (hamClient == null && hamListener.Pending())
                    {
                        hamClient = hamListener.AcceptTcpClient();
                        hamClient.NoDelay = true;
                        hamStream = hamClient.GetStream();
                        hamStream.ReadTimeout = 50;
                        hamStream.WriteTimeout = 1000;
                        hamBuffer.Clear();
                        Log("VarAC Hamlib/PTT connected.");
                    }

                    PumpApp();
                    PumpHamlib();
                    PumpRadioRaw();
                    Thread.Sleep(2);
                }
                catch (IOException)
                {
                    // One of the TCP connections ended. Check and reconnect each one independently.
                    if (client != null && !IsSocketAlive(client)) DisconnectClient("CAT TCP connection closed.");
                    if (hamClient != null && !IsSocketAlive(hamClient)) DisconnectHam("Hamlib/PTT connection closed.");
                }
                catch (SocketException)
                {
                    if (client != null && !IsSocketAlive(client)) DisconnectClient("CAT TCP connection closed.");
                    if (hamClient != null && !IsSocketAlive(hamClient)) DisconnectHam("Hamlib/PTT connection closed.");
                }
            }
        }

        private bool InitializeRadio()
        {
            Log("RADIO INIT START: native SATELLITE full-duplex");

            // 1) Native SATELLITE mode must be ON.
            int sat = ReadBinaryFunction(0x5A,"SATELLITE");
            if (sat < 0) return false;
            if (sat != 1)
            {
                if (!SendAckCommand(BuildCommand(new byte[]{0x16,0x5A,0x01}),900,
                    "INIT SATELLITE ON (16 5A 01)")) return false;
                Thread.Sleep(300);
                sat = ReadBinaryFunction(0x5A,"SATELLITE");
                if (sat != 1)
                {
                    Log("INIT ERROR: SATELLITE ON readback failed.");
                    return false;
                }
            }
            Log("INIT OK: SATELLITE = ON");

            // Optional defined QO-100 start frequency.
            if (startupSetFreq)
            {
                if (startupRxHz < rxMin || startupRxHz > rxMax)
                {
                    Log(String.Format("INIT SAFETY STOP: configured startup D0/RX {0} Hz outside RX window {1}..{2}.",
                        startupRxHz,rxMin,rxMax));
                    return false;
                }

                if (startupTxHz < txMin || startupTxHz > txMax)
                {
                    Log(String.Format("INIT SAFETY STOP: calculated startup D1/TX {0} Hz outside TX window {1}..{2}.",
                        startupTxHz,txMin,txMax));
                    return false;
                }

                Log(String.Format("INIT START FREQUENCIES: ON | D0/RX {0:F6} MHz | D1/TX {1:F6} MHz",
                    startupRxHz/1000000.0,startupTxHz/1000000.0));
            }
            else
            {
                Log("INIT START FREQUENCIES: OFF | existing IC-9700 SAT frequencies will be retained.");
            }

            // 2) D0 = RX/downlink.
            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD0}),900,
                "INIT select SAT D0/RX (07 D0)")) return false;
            if (!SetSelectedUsbD("D0/RX","INIT D0")) return false;

            if (startupSetFreq)
            {
                if (!SendAckCommand(BuildSetFreq05(startupRxHz),900,
                    "INIT set D0/RX startup frequency (05)")) return false;
                Thread.Sleep(200);
            }

            long d0Hz = ReadSelectedFrequencyInit("D0/RX");
            if (d0Hz < rxMin || d0Hz > rxMax)
            {
                Log(String.Format("INIT SAFETY STOP: D0/RX {0} Hz outside RX window {1}..{2}.",
                    d0Hz,rxMin,rxMax));
                return false;
            }
            if (startupSetFreq && d0Hz != startupRxHz)
            {
                Log(String.Format("INIT ERROR: D0/RX startup readback mismatch. Wanted {0}, got {1} Hz.",
                    startupRxHz,d0Hz));
                return false;
            }

            lastRxHz = d0Hz;
            Log(String.Format("INIT OK: D0/RX = {0:F6} MHz",d0Hz/1000000.0));

            // 3) D1 = TX/uplink.
            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD1}),900,
                "INIT select SAT D1/TX (07 D1)")) return false;
            if (!SetSelectedUsbD("D1/TX","INIT D1")) return false;

            if (startupSetFreq)
            {
                if (!SendAckCommand(BuildSetFreq05(startupTxHz),900,
                    "INIT set D1/TX startup frequency (05)")) return false;
                Thread.Sleep(200);
            }

            long d1Hz = ReadSelectedFrequencyInit("D1/TX");
            if (d1Hz < txMin || d1Hz > txMax)
            {
                Log(String.Format("INIT SAFETY STOP: D1/TX {0} Hz outside TX window {1}..{2}.",
                    d1Hz,txMin,txMax));
                return false;
            }
            if (startupSetFreq && d1Hz != startupTxHz)
            {
                Log(String.Format("INIT ERROR: D1/TX startup readback mismatch. Wanted {0}, got {1} Hz.",
                    startupTxHz,d1Hz));
                return false;
            }

            lastTxHz = d1Hz;
            Log(String.Format("INIT OK: D1/TX = {0:F6} MHz",d1Hz/1000000.0));

            // 4) Return to D0 and verify D0 did not move after the D1 write.
            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD0}),900,
                "INIT select SAT D0/RX final (07 D0)")) return false;

            long d0FinalHz = ReadSelectedFrequencyInit("D0/RX final");
            if (d0FinalHz < rxMin || d0FinalHz > rxMax)
            {
                Log("INIT SAFETY STOP: final D0/RX readback outside RX window.");
                return false;
            }

            if (startupSetFreq && d0FinalHz != startupRxHz)
            {
                Log(String.Format("INIT ERROR: D0/RX moved after D1 write. Wanted {0}, got {1} Hz.",
                    startupRxHz,d0FinalHz));
                return false;
            }

            lastRxHz = d0FinalHz;

            if (ReadBinaryFunction(0x5A,"SATELLITE") != 1)
            {
                Log("INIT ERROR: final SATELLITE state is not ON.");
                return false;
            }

            Log(String.Format(
                "RADIO INIT COMPLETE: SATELLITE ON | D0/RX {0:F6} MHz USB-D | D1/TX {1:F6} MHz USB-D | D0 selected.",
                lastRxHz/1000000.0,lastTxHz/1000000.0));
            return true;
        }

        private long ReadSelectedFrequencyInit(string name)
        {
            byte[] response = SendInitQuery(
                BuildCommand(new byte[]{0x03}),
                0x03,-1,900,
                "INIT READ " + name + " frequency (03)");

            long hz=-1;
            if (response == null || response.Length < 11 ||
                !TryDecodeBcdFrequency(response,5,out hz))
            {
                Log("INIT ERROR: " + name + " frequency readback failed.");
                return -1;
            }

            return hz;
        }

        private int ReadBinaryFunction(byte subCommand,string name)
        {
            byte[] response = SendInitQuery(
                BuildCommand(new byte[]{0x16,subCommand}),
                0x16,subCommand,900,
                "INIT READ " + name + " (16 " + subCommand.ToString("X2",CultureInfo.InvariantCulture) + ")");

            if (response == null || response.Length < 8)
            {
                Log("INIT ERROR: " + name + " readback missing.");
                return -1;
            }

            byte value = response[6];
            if (value != 0x00 && value != 0x01)
            {
                Log("INIT ERROR: " + name + " unexpected value " + value.ToString("X2",CultureInfo.InvariantCulture));
                return -1;
            }

            Log("INIT READBACK: " + name + " = " + (value == 0x01 ? "ON" : "OFF"));
            return value;
        }

        private bool SetSelectedUsbD(string vfoName,string step)
        {
            // Tested IC-9700 path:
            // 06 01 01       -> USB, filter 1
            // 1A 06 01 02    -> DATA ON, filter 2 (USB-D)
            // Do not use 0x26 for startup mode setting.
            if (!SendAckCommand(BuildCommand(new byte[]{0x06,0x01,0x01}),900,
                step + "a " + vfoName + " -> USB/filter 1 (06 01 01)")) return false;

            if (!SendAckCommand(BuildCommand(new byte[]{0x1A,0x06,0x01,0x02}),900,
                step + "b " + vfoName + " -> DATA ON/filter 2 (1A 06 01 02)")) return false;

            Thread.Sleep(250);

            byte[] mode = SendInitQuery(
                BuildCommand(new byte[]{0x04}),
                0x04,-1,900,
                step + "c " + vfoName + " base-mode readback (04)");

            if (mode == null || mode.Length < 8 || mode[5] != 0x01 || mode[6] != 0x02)
            {
                Log("INIT ERROR: " + vfoName + " base-mode readback is not USB/filter 2.");
                return false;
            }

            byte[] data = SendInitQuery(
                BuildCommand(new byte[]{0x1A,0x06}),
                0x1A,0x06,900,
                step + "d " + vfoName + " DATA readback (1A 06)");

            if (data == null || data.Length < 9 || data[6] != 0x01 || data[7] != 0x02)
            {
                Log("INIT ERROR: " + vfoName + " DATA readback is not ON/filter 2.");
                return false;
            }

            Log("INIT OK: " + vfoName + " = USB-D");
            return true;
        }

        private byte[] SendInitQuery(byte[] command,byte expectedCmd,int expectedSubCmd,
                                     int timeoutMs,string label)
        {
            DrainRadioToApp();
            Log(label + " | TX " + Hex(command));
            radio.Write(command,0,command.Length);

            Stopwatch sw=Stopwatch.StartNew();
            List<byte> buf=new List<byte>();

            while (sw.ElapsedMilliseconds < timeoutMs)
            {
                ReadInto(radio,buf);
                byte[] f;

                while (TryExtractFrame(buf,out f))
                {
                    Log(label + " | RX " + Hex(f));

                    // Ignore local CI-V echo.
                    if (f.Length >= 6 && f[2] == civ && f[3] == 0xE0) continue;

                    if (f.Length >= 6 && f[4] == 0xFA)
                    {
                        Log(label + " | NG (FA)");
                        return null;
                    }

                    if (f.Length < 6 || f[4] != expectedCmd) continue;
                    if (expectedSubCmd >= 0)
                    {
                        if (f.Length < 7 || f[5] != (byte)expectedSubCmd) continue;
                    }

                    return f;
                }

                Thread.Sleep(2);
            }

            Log(label + " | TIMEOUT after " + timeoutMs + " ms");
            return null;
        }

        private static bool IsSocketAlive(TcpClient c)
        {
            try
            {
                if (c == null || c.Client == null) return false;
                return !(c.Client.Poll(1, SelectMode.SelectRead) && c.Client.Available == 0);
            }
            catch { return false; }
        }

        private void DisconnectClient(string reason)
        {
            Log(reason + " Waiting for reconnection ...");
            try { if (app != null) app.Close(); } catch { }
            try { if (client != null) client.Close(); } catch { }
            app = null; client = null; appBuffer.Clear();
        }

        private void DisconnectHam(string reason)
        {
            Log(reason + " Waiting for Hamlib/PTT reconnection ...");
            try { if (hamStream != null) hamStream.Close(); } catch { }
            try { if (hamClient != null) hamClient.Close(); } catch { }
            hamStream = null; hamClient = null; hamBuffer.Clear();
        }

        private void PumpHamlib()
        {
            if (hamStream == null || !hamStream.DataAvailable) return;
            byte[] buf = new byte[2048];
            int got = hamStream.Read(buf,0,buf.Length);
            if (got == 0) { DisconnectHam("VarAC closed the Hamlib/PTT connection."); return; }
            hamBuffer.Append(Encoding.ASCII.GetString(buf,0,got));
            string line;
            while (TryExtractHamLine(out line)) HandleHamlibLine(line);
        }

        private bool TryExtractHamLine(out string line)
        {
            line = null;
            for (int i=0;i<hamBuffer.Length;i++)
            {
                char ch = hamBuffer[i];
                if (ch == '\r' || ch == '\n')
                {
                    line = hamBuffer.ToString(0,i);
                    int remove = i + 1;
                    while (remove < hamBuffer.Length && (hamBuffer[remove] == '\r' || hamBuffer[remove] == '\n')) remove++;
                    hamBuffer.Remove(0,remove);
                    return true;
                }
            }
            return false;
        }

        private void HandleHamlibLine(string raw)
        {
            string line = (raw ?? "").Trim();
            if (line.Length == 0) return;
            Log("HAMLIB RX: " + line);

            if (line.StartsWith("+")) line = line.Substring(1).TrimStart();
            string[] p = line.Split(new char[]{' ','\t'}, StringSplitOptions.RemoveEmptyEntries);
            if (p.Length == 0) return;
            string cmd = p[0];

            if (String.Equals(cmd,"T",StringComparison.Ordinal) ||
                String.Equals(cmd,"set_ptt",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(cmd,"\\set_ptt",StringComparison.OrdinalIgnoreCase))
            {
                int v;
                if (p.Length < 2 || !Int32.TryParse(p[1],NumberStyles.Integer,CultureInfo.InvariantCulture,out v))
                {
                    HamWrite("RPRT -1\n"); return;
                }
                bool ok = SetPtt(v != 0);
                HamWrite(ok ? "RPRT 0\n" : "RPRT -1\n");
                return;
            }

            if (String.Equals(cmd,"t",StringComparison.Ordinal) ||
                String.Equals(cmd,"get_ptt",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(cmd,"\\get_ptt",StringComparison.OrdinalIgnoreCase))
            {
                HamWrite(pttState ? "1\n" : "0\n"); return;
            }

            // Some programs query the frequency when connecting. This is only a reply;
            // the actual VarAC frequency control remains exclusively on CAT port 9701.
            if (String.Equals(cmd,"f",StringComparison.Ordinal) ||
                String.Equals(cmd,"get_freq",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(cmd,"\\get_freq",StringComparison.OrdinalIgnoreCase))
            {
                HamWrite((lastRxHz > 0 ? lastRxHz : 0).ToString(CultureInfo.InvariantCulture) + "\n"); return;
            }

            if (String.Equals(cmd,"q",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(cmd,"quit",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(cmd,"\\quit",StringComparison.OrdinalIgnoreCase))
            {
                HamWrite("RPRT 0\n"); DisconnectHam("Hamlib/PTT client disconnected."); return;
            }

            // Explicitly reject unknown rigctld commands.
            HamWrite("RPRT -1\n");
        }

        private void HamWrite(string text)
        {
            if (hamStream == null) return;
            try
            {
                byte[] b = Encoding.ASCII.GetBytes(text);
                hamStream.Write(b,0,b.Length);
                hamStream.Flush();
            }
            catch { DisconnectHam("Hamlib/PTT write failed."); }
        }

        private bool SetPtt(bool on)
        {
            if (on)
            {
                if (pttState)
                {
                    Log("PTT ON requested while already transmitting -> no action.");
                    return true;
                }

                // Native IC-9700 SATELLITE full-duplex was confirmed operational:
                // D0 remains the 433 MHz downlink receiver while D1 transmits on 144 MHz.
                // No D0/D1 selection and no XCHG are required for PTT.
                if (lastTxHz < txMin || lastTxHz > txMax)
                {
                    Log(String.Format("PTT SAFETY STOP: cached D1/TX {0} Hz is outside TX window.",lastTxHz));
                    return false;
                }

                Log(String.Format("PTT ON: native SAT full-duplex | D1/TX {0:F6} MHz | D0/RX remains active.",
                    lastTxHz/1000000.0));

                if (!SendAckCommand(BuildCommand(new byte[]{0x1C,0x00,0x01}),700,
                    "PTT TX ON (1C 00 01)"))
                {
                    // Fail safe: explicitly request RX if TX ON was not cleanly acknowledged.
                    SendAckCommand(BuildCommand(new byte[]{0x1C,0x00,0x00}),700,
                        "PTT ROLLBACK TX OFF (1C 00 00)");
                    pttState = false;
                    return false;
                }

                pttState = true;
                Log("PTT = TX | native SAT full-duplex active.");
                return true;
            }
            else
            {
                if (!pttState)
                {
                    // Duplicate OFF: still send the confirmed native SAT PTT OFF command.
                    bool duplicateOff = SendAckCommand(BuildCommand(new byte[]{0x1C,0x00,0x00}),700,
                        "PTT OFF duplicate (1C 00 00)");
                    Log("PTT OFF requested while already receiving.");
                    return duplicateOff;
                }

                Log("PTT OFF: native SAT full-duplex -> RX.");

                bool ok = SendAckCommand(BuildCommand(new byte[]{0x1C,0x00,0x00}),700,
                    "PTT TX OFF (1C 00 00)");

                if (ok)
                {
                    pttState = false;
                    Log("PTT = RX | D0/downlink remains the receive side.");
                }
                else
                {
                    Log("PTT OFF ERROR: radio did not acknowledge TX OFF.");
                }

                return ok;
            }
        }

        private void PumpApp()
        {
            if (app == null || !app.DataAvailable) return;
            byte[] buf = new byte[4096];
            int got = app.Read(buf,0,buf.Length);
            if (got == 0) { DisconnectClient("VarAC closed the connection."); return; }
            for (int i=0;i<got;i++) appBuffer.Add(buf[i]);
            byte[] frame;
            while (TryExtractFrame(appBuffer,out frame)) ProcessAppFrame(frame);
        }

        private void PumpRadioRaw()
        {
            if (app == null) return;
            int n = radio.BytesToRead;
            if (n <= 0) return;
            byte[] b = new byte[Math.Min(n,4096)];
            int got = radio.Read(b,0,b.Length);
            if (got > 0) AppWrite(b);
        }

        private void ProcessAppFrame(byte[] f)
        {
            if (!IsCiv(f)) { Forward(f); return; }
            byte cmd = f[4];

            // VarAC Standard: 25 00 + 5 BCD bytes.
            if (cmd == 0x25 && f.Length == 12 && f[5] == 0x00)
            {
                long hz; if (!TryDecodeBcdFrequency(f,6,out hz)) { ReplyAck(f,false); return; }
                HandleSetFrequency(f,hz); return;
            }
            // Also support the classic 05 frequency-set command.
            if (cmd == 0x05 && f.Length == 11)
            {
                long hz; if (!TryDecodeBcdFrequency(f,5,out hz)) { ReplyAck(f,false); return; }
                HandleSetFrequency(f,hz); return;
            }

            // V5.01 initializes D0/RX and D1/TX to USB-D using the tested 06 + 1A 06 path.
            // VarAC 0x26 mode commands remain acknowledged locally and are NOT sent to the radio.
            // 0x26 is deliberately avoided in IC-9700 SATELLITE mode.
            if (ignoreMode && cmd == 0x26)
            {
                Log("VarAC mode command 26 intercepted (radio mode remains unchanged).");
                ReplyAck(f,true); return;
            }

            // Frequency readback: return SAT D0/RX.
            if (cmd == 0x25 && f.Length == 7 && f[5] == 0x00)
            {
                long hz = QueryRxFrequency();
                if (hz > 0) ReplyFrequency25(f,hz); else ReplyAck(f,false);
                return;
            }
            if (cmd == 0x03 && f.Length == 6)
            {
                long hz = QueryRxFrequency();
                if (hz > 0) ReplyFrequency03(f,hz); else ReplyAck(f,false);
                return;
            }

            // Direct CAT PTT 1C 00 01/00 is native SAT-safe; Hamlib/PTT is the primary configured path.
            Forward(f);
        }

        private void HandleSetFrequency(byte[] request,long rxHz)
        {
            if (rxHz < rxMin || rxHz > rxMax)
            {
                Log(String.Format("Frequency {0} Hz is outside the 433 MHz proxy window -> forwarded unchanged.",rxHz));
                Forward(request); return;
            }
            long txHz = rxHz - delta;
            if (txHz < txMin || txHz > txMax)
            {
                Log(String.Format("SAFETY STOP: RX {0} -> invalid TX IF {1}.",rxHz,txHz));
                ReplyAck(request,false); return;
            }
            bool ok = SetBothFrequencies(rxHz,txHz);
            if (ok)
            {
                lastRxHz = rxHz;
                Log(String.Format("FREQ: SAT D0/RX {0:F6} MHz | SAT D1/TX {1:F6} MHz",
                    rxHz/1000000.0, txHz/1000000.0));
            }
            else Log("ERROR while setting RX/TX.");
            ReplyAck(request,ok);
        }

        private bool SetBothFrequencies(long rxHz,long txHz)
        {
            // Confirmed native IC-9700 SATELLITE mapping:
            //   D0 = 433 MHz RX/downlink IF
            //   D1 = 144 MHz TX/uplink IF
            // Command 05 sets each selected SAT side independently; the other side did not track.
            Log(String.Format("SAT SET START: D0/RX {0:F6} MHz | D1/TX {1:F6} MHz",
                rxHz/1000000.0, txHz/1000000.0));

            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD0}),700,
                "SAT QSY 1/5 select D0/RX (07 D0)")) return false;

            if (!SendAckCommand(BuildSetFreq05(rxHz),700,
                "SAT QSY 2/5 set D0/RX frequency (05)")) return false;

            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD1}),700,
                "SAT QSY 3/5 select D1/TX (07 D1)")) return false;

            if (!SendAckCommand(BuildSetFreq05(txHz),700,
                "SAT QSY 4/5 set D1/TX frequency (05)")) return false;

            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD0}),700,
                "SAT QSY 5/5 select D0/RX again (07 D0)")) return false;

            lastRxHz = rxHz;
            lastTxHz = txHz;

            Log("SAT SET OK: D0/RX and D1/TX acknowledged with FB; D0/RX selected.");
            return true;
        }

        private long QueryRxFrequency()
        {
            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD0}),700,"RX read: select SAT D0/RX")) return lastRxHz;
            byte[] response = SendQuery(BuildCommand(new byte[]{0x03}),0x03,900);
            long hz=-1;
            if (response != null && response.Length >= 11) TryDecodeBcdFrequency(response,5,out hz);
            if (hz > 0) lastRxHz = hz;
            return hz > 0 ? hz : lastRxHz;
        }

        private void Forward(byte[] f)
        {
            radio.Write(f,0,f.Length);
            if (f.Length >= 8 && f[4] == 0x1C && f[5] == 0x00)
                Log(f[6] == 0x01 ? "PTT -> TX (from VarAC)" : "PTT -> RX (from VarAC)");
        }

        private bool SendAckCommand(byte[] command,int timeoutMs,string label)
        {
            DrainRadioToApp();
            Log(label + " | TX " + Hex(command));
            radio.Write(command,0,command.Length);
            Stopwatch sw=Stopwatch.StartNew(); List<byte> buf=new List<byte>();
            while (sw.ElapsedMilliseconds < timeoutMs)
            {
                ReadInto(radio,buf); byte[] f;
                while (TryExtractFrame(buf,out f))
                {
                    Log(label + " | RX " + Hex(f));
                    if (f.Length >= 6 && f[2] == civ && f[3] == 0xE0) continue; // local echo
                    if (f.Length >= 6 && f[4] == 0xFB) { Log(label + " | OK (FB)"); return true; }
                    if (f.Length >= 6 && f[4] == 0xFA) { Log(label + " | NG (FA)"); return false; }
                }
                Thread.Sleep(2);
            }
            Log(label + " | TIMEOUT after " + timeoutMs + " ms");
            return false;
        }

        private static string Hex(byte[] data)
        {
            if (data == null) return "<null>";
            StringBuilder sb = new StringBuilder(data.Length*3);
            for (int i=0;i<data.Length;i++)
            {
                if (i>0) sb.Append(' ');
                sb.Append(data[i].ToString("X2",CultureInfo.InvariantCulture));
            }
            return sb.ToString();
        }

        private byte[] SendQuery(byte[] command,byte expectedCmd,int timeoutMs)
        {
            DrainRadioToApp();
            Log("QUERY | TX " + Hex(command));
            radio.Write(command,0,command.Length);
            Stopwatch sw=Stopwatch.StartNew(); List<byte> buf=new List<byte>();
            while (sw.ElapsedMilliseconds < timeoutMs)
            {
                ReadInto(radio,buf); byte[] f;
                while (TryExtractFrame(buf,out f))
                {
                    Log("QUERY | RX " + Hex(f));
                    if (f.Length >= 6 && f[2] == civ && f[3] == 0xE0) continue;
                    if (f.Length >= 6 && f[4] == 0xFA) return null;
                    if (f.Length >= 6 && f[4] == expectedCmd) return f;
                }
                Thread.Sleep(2);
            }
            return null;
        }

        private static void ReadInto(SerialPort p,List<byte> target)
        {
            int n=p.BytesToRead; if (n<=0) return;
            byte[] tmp=new byte[Math.Min(n,4096)]; int got=p.Read(tmp,0,tmp.Length);
            for (int i=0;i<got;i++) target.Add(tmp[i]);
        }

        private void DrainRadioToApp()
        {
            int loops=0;
            while (radio.BytesToRead > 0 && loops++ < 20)
            {
                int n=Math.Min(radio.BytesToRead,4096); byte[] b=new byte[n];
                int got=radio.Read(b,0,b.Length); if (got>0 && app!=null) AppWrite(b);
                Thread.Sleep(1);
            }
        }

        private void AppWrite(byte[] b)
        {
            if (app == null) return;
            app.Write(b,0,b.Length); app.Flush();
        }

        private byte[] BuildCommand(byte[] payload)
        {
            byte[] f=new byte[4+payload.Length+1];
            f[0]=0xFE; f[1]=0xFE; f[2]=civ; f[3]=0xE0;
            Buffer.BlockCopy(payload,0,f,4,payload.Length); f[f.Length-1]=0xFD; return f;
        }

        private byte[] BuildSetFreq05(long hz)
        {
            byte[] bcd=EncodeBcdFrequency(hz); byte[] payload=new byte[1+bcd.Length];
            payload[0]=0x05; Buffer.BlockCopy(bcd,0,payload,1,bcd.Length); return BuildCommand(payload);
        }

        private static byte[] EncodeBcdFrequency(long hz)
        {
            string s=hz.ToString("D10",CultureInfo.InvariantCulture);
            if (s.Length>10) throw new ArgumentOutOfRangeException("hz");
            byte[] o=new byte[5];
            for (int pair=0;pair<5;pair++)
            {
                int src=8-(pair*2); int hi=s[src]-'0'; int lo=s[src+1]-'0';
                o[pair]=(byte)((hi<<4)|lo);
            }
            return o;
        }

        private static bool TryDecodeBcdFrequency(byte[] data,int offset,out long hz)
        {
            hz=-1; if (data==null || offset<0 || offset+5>data.Length) return false;
            StringBuilder s=new StringBuilder(10);
            for (int i=4;i>=0;i--)
            {
                byte b=data[offset+i]; int hi=(b>>4)&0x0F; int lo=b&0x0F;
                if (hi>9 || lo>9) return false;
                s.Append((char)('0'+hi)); s.Append((char)('0'+lo));
            }
            return Int64.TryParse(s.ToString(),NumberStyles.None,CultureInfo.InvariantCulture,out hz);
        }

        private void ReplyAck(byte[] request,bool ok)
        {
            byte controller=request.Length>3?request[3]:(byte)0xE0;
            byte target=request.Length>2?request[2]:civ;
            AppWrite(new byte[]{0xFE,0xFE,controller,target,ok?(byte)0xFB:(byte)0xFA,0xFD});
        }

        private void ReplyFrequency25(byte[] request,long hz)
        {
            byte[] bcd=EncodeBcdFrequency(hz); byte[] r=new byte[12];
            r[0]=0xFE;r[1]=0xFE;r[2]=request[3];r[3]=request[2];r[4]=0x25;r[5]=0x00;
            Buffer.BlockCopy(bcd,0,r,6,5);r[11]=0xFD;AppWrite(r);
        }
        private void ReplyFrequency03(byte[] request,long hz)
        {
            byte[] bcd=EncodeBcdFrequency(hz); byte[] r=new byte[11];
            r[0]=0xFE;r[1]=0xFE;r[2]=request[3];r[3]=request[2];r[4]=0x03;
            Buffer.BlockCopy(bcd,0,r,5,5);r[10]=0xFD;AppWrite(r);
        }

        private static bool IsCiv(byte[] f)
        { return f!=null && f.Length>=6 && f[0]==0xFE && f[1]==0xFE && f[f.Length-1]==0xFD; }

        private static bool TryExtractFrame(List<byte> buffer,out byte[] frame)
        {
            frame=null; if (buffer.Count<3) return false;
            int start=-1;
            for (int i=0;i<buffer.Count-1;i++) if (buffer[i]==0xFE && buffer[i+1]==0xFE) {start=i;break;}
            if (start<0)
            {
                byte last=buffer[buffer.Count-1]; buffer.Clear(); if (last==0xFE) buffer.Add(last); return false;
            }
            if (start>0) buffer.RemoveRange(0,start);
            int end=-1; for (int i=2;i<buffer.Count;i++) if (buffer[i]==0xFD) {end=i;break;}
            if (end<0) return false;
            frame=buffer.GetRange(0,end+1).ToArray(); buffer.RemoveRange(0,end+1); return true;
        }

        private void Log(string msg)
        {
            string line=DateTime.Now.ToString("HH:mm:ss.fff",CultureInfo.InvariantCulture)+"  "+msg;
            Console.WriteLine(line); try { File.AppendAllText(logFile,line+Environment.NewLine,Encoding.UTF8); } catch { }
        }

        public void Dispose()
        {
            try { if (app!=null) app.Close(); } catch { }
            try { if (client!=null) client.Close(); } catch { }
            try { listener.Stop(); } catch { }
            try { hamListener.Stop(); } catch { }
            try { if (hamStream!=null) hamStream.Close(); } catch { }
            try { if (hamClient!=null) hamClient.Close(); } catch { }
            try { if (radio!=null && radio.IsOpen) radio.Close(); } catch { }
            try { if (radio!=null) radio.Dispose(); } catch { }
        }
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies 'System.dll'

Write-Host ''
Write-Host 'VarAC QSY-CAT Proxy for IC-9700 by HBØTR V5.01' -ForegroundColor Cyan
Write-Host 'Author HBØTR Stefan Franz | https://www.qrz.com/db/HB0TR'
Write-Host ('CAT/Frequency: {0}:{1}   Hamlib/PTT: {2}:{3}' -f $listenHost,$listenPort,$hamHost,$hamPort)
Write-Host ('Radio: {0}   Baud: {1}' -f $radioPort,$baud)
Write-Host ('RX/TX offset: {0} Hz' -f $rxTxDelta)
Write-Host ('Startup frequencies: {0}' -f $(if ($startupSetFreq) {'ON'} else {'OFF'}))
if ($startupSetFreq) {
    Write-Host ('  QO-100 DL RF:   {0:F6} MHz' -f ($qo100DlRfHz/1000000.0))
    Write-Host ('  RX converter LO:{0:F6} MHz' -f ($rxConverterLoHz/1000000.0))
    Write-Host ('  D0/RX IF:       {0:F6} MHz' -f ($startupRxHz/1000000.0))
    Write-Host ('  D1/TX IF:       {0:F6} MHz' -f ($startupTxHz/1000000.0))
}
Write-Host ''
Write-Host 'V5.01 native SAT full-duplex: QO100_DL_RF_HZ defines the startup downlink RF; D0/RX and D1/TX IFs are derived automatically.' -ForegroundColor Yellow
Write-Host ''

$proxy = New-Object -TypeName QO100CatProxyV501.Proxy -ArgumentList @(
    $listenHost,$listenPort,$hamHost,$hamPort,$radioPort,$baud,$civAddr,
    $rxTxDelta,$rxMin,$rxMax,$txMin,$txMax,
    $startupSetFreq,$startupRxHz,$startupTxHz,
    $ignoreMode,$logPath
)
try { $proxy.Run() } finally { $proxy.Dispose() }
