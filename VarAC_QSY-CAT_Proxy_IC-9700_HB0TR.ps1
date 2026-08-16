# VarAC QSY-CAT Proxy for IC-9700 by HBØTR V5.00
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

namespace QO100CatProxyV5
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
        private readonly bool ignoreMode;
        private readonly string logFile;
        private readonly List<byte> appBuffer = new List<byte>();
        private readonly StringBuilder hamBuffer = new StringBuilder();
        private long lastRxHz = -1;
        private bool pttState = false;

        public Proxy(string host, int port, string hamHost, int hamPort, string radioPort, int baud, byte civAddress,
                     long deltaHz, long rxIfMinHz, long rxIfMaxHz, long txIfMinHz, long txIfMaxHz,
                     bool ignoreModeCommands, string logPath)
        {
            listener = new TcpListener(IPAddress.Parse(host), port);
            hamListener = new TcpListener(IPAddress.Parse(hamHost), hamPort);
            civ = civAddress; delta = deltaHz; rxMin = rxIfMinHz; rxMax = rxIfMaxHz;
            txMin = txIfMinHz; txMax = txIfMaxHz; ignoreMode = ignoreModeCommands; logFile = logPath;
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
            Log("=== VarAC QSY-CAT Proxy for IC-9700 by HBØTR V5.00 started ===");
            Log("Author HBØTR Stefan Franz | https://www.qrz.com/db/HB0TR");
            Log("RADIO SETUP: IC-9700 must be in normal VFO mode; SATELLITE mode OFF; set USB-D manually.");
            Log(String.Format("CAT/Frequency: {0} | Hamlib/PTT: {1} | Radio: {2} | {3} baud | CI-V {4:X2}h",
                ((IPEndPoint)listener.LocalEndpoint), ((IPEndPoint)hamListener.LocalEndpoint), radio.PortName, radio.BaudRate, civ));
            radio.Open();
            listener.Start();
            hamListener.Start();
            Log("COM port to the IC-9700 is open.");
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
                Log("PTT ON: select SUB/TX and transmit.");
                if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD1}),700,"PTT 1/2 select SUB/TX (07 D1)")) return false;
                if (!SendAckCommand(BuildCommand(new byte[]{0x1C,0x00,0x01}),700,"PTT 2/2 TX ON (1C 00 01)")) return false;
                pttState = true;
                Log("PTT = TX");
                return true;
            }
            else
            {
                Log("PTT OFF: return to receive and select MAIN/RX.");
                bool a = SendAckCommand(BuildCommand(new byte[]{0x1C,0x00,0x00}),700,"PTT 1/2 TX OFF (1C 00 00)");
                bool b = SendAckCommand(BuildCommand(new byte[]{0x07,0xD0}),700,"PTT 2/2 select MAIN/RX (07 D0)");
                if (a) pttState = false;
                if (a && b) Log("PTT = RX");
                return a && b;
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

            // During direct CAT testing, ModeUSB_D caused unintended TX behavior.
            // The supported station setup keeps the IC-9700 in normal VFO mode with SATELLITE mode OFF.
            // Therefore, mode commands are acknowledged to VarAC by default but are NOT sent to the radio.
            if (ignoreMode && cmd == 0x26)
            {
                Log("VarAC mode command 26 intercepted (radio mode remains unchanged).");
                ReplyAck(f,true); return;
            }

            // Frequency readback: return RX/MAIN.
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

            // Forward PTT 1C 00 01/00 and other commands unchanged.
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
                Log(String.Format("FREQ: RX/MAIN {0:F6} MHz | TX/SUB {1:F6} MHz",
                    rxHz/1000000.0, txHz/1000000.0));
            }
            else Log("ERROR while setting RX/TX.");
            ReplyAck(request,ok);
        }

        private bool SetBothFrequencies(long rxHz,long txHz)
        {
            // Supported IC-9700 setup: normal VFO mode, SATELLITE mode OFF.
            // MAIN = 433 MHz RX/downlink IF, SUB = 144 MHz TX/uplink IF.
            // Therefore set MAIN to RX first, then SUB to TX, and finally select MAIN again.
            Log(String.Format("SET START: RX/MAIN {0:F6} MHz | TX/SUB {1:F6} MHz",
                rxHz/1000000.0, txHz/1000000.0));

            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD0}),700,"1/5 select MAIN (07 D0)")) return false;
            if (!SendAckCommand(BuildSetFreq05(rxHz),700,"2/5 set RX frequency on MAIN (05)")) return false;
            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD1}),700,"3/5 select SUB (07 D1)")) return false;
            if (!SendAckCommand(BuildSetFreq05(txHz),700,"4/5 set TX frequency on SUB (05)")) return false;
            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD0}),700,"5/5 select MAIN again (07 D0)")) return false;
            Log("SET OK: IC-9700 acknowledged RX/MAIN and TX/SUB with FB.");
            return true;
        }

        private long QueryRxFrequency()
        {
            if (!SendAckCommand(BuildCommand(new byte[]{0x07,0xD0}),700,"RX read: select MAIN")) return lastRxHz;
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
Write-Host 'VarAC QSY-CAT Proxy for IC-9700 by HBØTR V5.00' -ForegroundColor Cyan
Write-Host 'Author HBØTR Stefan Franz | https://www.qrz.com/db/HB0TR'
Write-Host ('CAT/Frequency: {0}:{1}   Hamlib/PTT: {2}:{3}' -f $listenHost,$listenPort,$hamHost,$hamPort)
Write-Host ('Radio: {0}   Baud: {1}' -f $radioPort,$baud)
Write-Host ('RX/TX offset: {0} Hz' -f $rxTxDelta)
Write-Host ''
Write-Host 'IMPORTANT: Frequency control stays on CAT/TCP 9701. PTT uses separate Hamlib port 4532. Keep TX power minimal for the first test.' -ForegroundColor Yellow
Write-Host ''

$proxy = New-Object -TypeName QO100CatProxyV5.Proxy -ArgumentList @(
    $listenHost,$listenPort,$hamHost,$hamPort,$radioPort,$baud,$civAddr,
    $rxTxDelta,$rxMin,$rxMax,$txMin,$txMax,$ignoreMode,$logPath
)
try { $proxy.Run() } finally { $proxy.Dispose() }
