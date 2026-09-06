# Open-CashDrawer.ps1
# Always-on-top button that kicks open a USB cash drawer on Windows.
#
# Two ways drawers are wired, pick one in the CONFIG block below:
#   'Printer' - drawer plugged into a receipt printer's RJ11/RJ12 "DK" port.
#               Sends an ESC/POS kick pulse as a RAW job to the Windows printer.
#   'COM'     - drawer (or its adapter, e.g. APG USBPro, Star SMD2) shows up
#               as a serial/COM port in Device Manager. Sends the kick bytes
#               straight to the port.
#
# Run:  powershell -ExecutionPolicy Bypass -File Open-CashDrawer.ps1
# (or double-click OpenCashDrawer.bat for a console-free launch)

# ============================ CONFIG =========================================

$Mode = 'Printer'            # 'Printer' or 'COM'

# --- Printer mode ---
# Exact name from Settings > Bluetooth & devices > Printers & scanners,
# e.g. 'EPSON TM-T20III Receipt' or 'Star TSP143'.
$PrinterName = 'EPSON TM-T20III Receipt'

# ESC/POS drawer kick: ESC p <pin> <on> <off>
# Pin 0 = drawer 1 (almost always the right one), pin 1 = drawer 2.
# 0x19,0xFA = 50ms on / 500ms off pulse. Works on Epson, Bixolon, Citizen,
# most generic printers. Star printers in Star line mode use 0x07 (BEL) instead;
# swap the array for: 0x07
[byte[]]$KickBytes = 0x1B, 0x70, 0x00, 0x19, 0xFA

# --- COM mode ---
$ComPort  = 'COM3'
$BaudRate = 9600
# Many serial drawers open on any byte; APG USBPro wants 'a' (0x61) by default.
# Reuse $KickBytes above or set port-specific bytes here:
[byte[]]$ComKickBytes = $KickBytes

# --- Browser / HTTP trigger ---
# When enabled, the app also listens on http://localhost:<port>/open so a web
# page's JavaScript can kick the drawer:
#   fetch('http://localhost:8737/open', { method: 'POST' })
# Loopback only - nothing outside this machine can reach it.
$EnableHttpTrigger = $true
$HttpPort          = 8737
$AllowedOrigin     = '*'   # tighten to your POS site, e.g. 'https://pos.example.com'

# --- Button appearance ---
$ButtonText = "OPEN`nDRAWER"
$WindowSize = 110            # px, square
$Opacity    = 0.95

# ============================ DRAWER TRIGGER =================================

# RAW printing via winspool.drv - the only way to push raw ESC/POS bytes
# through a Windows printer queue without a driver mangling them.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RawPrinter
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DOCINFOW
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool OpenPrinterW(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool ClosePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool StartDocPrinterW(IntPtr hPrinter, int level, ref DOCINFOW di);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndDocPrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool StartPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool WritePrinter(IntPtr hPrinter, byte[] pBytes, int dwCount, out int dwWritten);

    public static void Send(string printerName, byte[] data)
    {
        IntPtr h;
        if (!OpenPrinterW(printerName, out h, IntPtr.Zero))
            throw new Exception("Printer not found: " + printerName +
                " (Win32 error " + Marshal.GetLastWin32Error() + ")");
        try
        {
            var di = new DOCINFOW { pDocName = "Cash Drawer Kick", pDataType = "RAW" };
            if (!StartDocPrinterW(h, 1, ref di))
                throw new Exception("StartDocPrinter failed (error " + Marshal.GetLastWin32Error() + ")");
            try
            {
                StartPagePrinter(h);
                int written;
                if (!WritePrinter(h, data, data.Length, out written) || written != data.Length)
                    throw new Exception("WritePrinter failed (error " + Marshal.GetLastWin32Error() + ")");
                EndPagePrinter(h);
            }
            finally { EndDocPrinter(h); }
        }
        finally { ClosePrinter(h); }
    }
}
'@

function Open-Drawer {
    if ($Mode -eq 'Printer') {
        [RawPrinter]::Send($PrinterName, $KickBytes)
    }
    else {
        $port = New-Object System.IO.Ports.SerialPort $ComPort, $BaudRate, 'None', 8, 'One'
        try {
            $port.Open()
            $port.Write($ComKickBytes, 0, $ComKickBytes.Length)
        }
        finally {
            if ($port.IsOpen) { $port.Close() }
            $port.Dispose()
        }
    }
}

# ============================ UI =============================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Cash Drawer'
$form.FormBorderStyle = 'None'
$form.TopMost         = $true
$form.ShowInTaskbar   = $true
$form.StartPosition   = 'Manual'
$form.Size            = New-Object System.Drawing.Size($WindowSize, $WindowSize)
$form.Opacity         = $Opacity
$form.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)

# Bottom-right corner of the working area, clear of the taskbar.
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(($wa.Right - $WindowSize - 16), ($wa.Bottom - $WindowSize - 16))

$button = New-Object System.Windows.Forms.Button
$button.Text      = $ButtonText
$button.Dock      = 'Fill'
$button.FlatStyle = 'Flat'
$button.FlatAppearance.BorderSize = 2
$button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 150, 90)
$button.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 70)
$button.ForeColor = [System.Drawing.Color]::White
$button.Font      = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($button)

$flashTimer = New-Object System.Windows.Forms.Timer
$flashTimer.Interval = 700
$flashTimer.Add_Tick({
    $flashTimer.Stop()
    $button.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 70)
    $button.Text = $ButtonText
})

# Kicks the drawer and flashes the button. Returns $null on success,
# the error message on failure. Shared by the button and the HTTP trigger.
function Invoke-DrawerKick {
    $result = $null
    try {
        Open-Drawer
        $button.BackColor = [System.Drawing.Color]::FromArgb(0, 180, 100)   # green flash
    }
    catch {
        $button.BackColor = [System.Drawing.Color]::FromArgb(180, 40, 40)   # red flash
        $button.Text = 'ERROR'
        $result = $_.Exception.Message
    }
    $flashTimer.Stop()
    $flashTimer.Start()
    return $result
}

$button.Add_Click({
    if ($drag.Moved) { $drag.Moved = $false; return }
    $err = Invoke-DrawerKick
    if ($err) {
        [System.Windows.Forms.MessageBox]::Show($err, 'Cash Drawer', 'OK', 'Error') | Out-Null
    }
})

# Borderless window, so make it draggable from anywhere on the button.
$drag = @{ Active = $false; Start = $null; Moved = $false }
$button.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq 'Left') {
        $drag.Active = $true
        $drag.Start  = $e.Location
    }
})
$button.Add_MouseMove({
    param($s, $e)
    if ($drag.Active) {
        $dx = $e.X - $drag.Start.X
        $dy = $e.Y - $drag.Start.Y
        if ($drag.Moved -or [Math]::Abs($dx) -gt 3 -or [Math]::Abs($dy) -gt 3) {
            $drag.Moved = $true
            $form.Location = New-Object System.Drawing.Point(($form.Location.X + $dx), ($form.Location.Y + $dy))
        }
    }
})
$button.Add_MouseUp({ $drag.Active = $false })

# Right-click menu to quit (there's no title bar close button).
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add('Exit').Add_Click({ $form.Close() }) | Out-Null
$button.ContextMenuStrip = $menu

# ============================ HTTP TRIGGER ===================================
# A minimal HTTP server on 127.0.0.1 so browser JavaScript can fire the drawer.
# Raw TcpListener instead of HttpListener because loopback TcpListener needs no
# admin rights or netsh urlacl reservation. A WinForms timer polls Pending() on
# the UI thread, so the kick and button flash run on the right thread for free.

function Send-HttpResponse {
    param($Writer, [string]$Status, [string]$Body)
    $len = [System.Text.Encoding]::UTF8.GetByteCount($Body)
    $Writer.Write("HTTP/1.1 $Status`r`n")
    $Writer.Write("Access-Control-Allow-Origin: $AllowedOrigin`r`n")
    $Writer.Write("Access-Control-Allow-Methods: GET, POST, OPTIONS`r`n")
    $Writer.Write("Access-Control-Allow-Headers: *`r`n")
    # Chromium's Private Network Access preflight needs this to allow a public
    # https site to call localhost.
    $Writer.Write("Access-Control-Allow-Private-Network: true`r`n")
    $Writer.Write("Content-Type: application/json`r`n")
    $Writer.Write("Content-Length: $len`r`n")
    $Writer.Write("Connection: close`r`n`r`n")
    if ($len -gt 0) { $Writer.Write($Body) }
    $Writer.Flush()
}

if ($EnableHttpTrigger) {
    $httpListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $HttpPort)
    try {
        $httpListener.Start()
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "HTTP trigger disabled - couldn't listen on port ${HttpPort}: $($_.Exception.Message)",
            'Cash Drawer', 'OK', 'Warning') | Out-Null
        $httpListener = $null
    }

    if ($httpListener) {
        $httpTimer = New-Object System.Windows.Forms.Timer
        $httpTimer.Interval = 100
        $httpTimer.Add_Tick({
            while ($httpListener.Pending()) {
                $client = $null
                try {
                    $client = $httpListener.AcceptTcpClient()
                    $client.ReceiveTimeout = 1000
                    $stream = $client.GetStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $writer = New-Object System.IO.StreamWriter($stream)

                    $requestLine = $reader.ReadLine()
                    while (-not [string]::IsNullOrEmpty($reader.ReadLine())) { }   # drain headers

                    $parts  = "$requestLine" -split ' '
                    $method = $parts[0]
                    $path   = if ($parts.Count -gt 1) { $parts[1].Split('?')[0] } else { '' }

                    if ($method -eq 'OPTIONS') {
                        Send-HttpResponse $writer '204 No Content' ''
                    }
                    elseif ($path -eq '/open') {
                        $err = Invoke-DrawerKick
                        if ($null -eq $err) {
                            Send-HttpResponse $writer '200 OK' '{"ok":true}'
                        }
                        else {
                            $safe = $err -replace '[\\"]', "'" -replace '[\r\n\t]', ' '
                            Send-HttpResponse $writer '500 Internal Server Error' "{`"ok`":false,`"error`":`"$safe`"}"
                        }
                    }
                    else {
                        Send-HttpResponse $writer '404 Not Found' '{"ok":false,"error":"unknown path, use /open"}'
                    }
                }
                catch { }   # a hung or malformed client shouldn't kill the app
                finally {
                    if ($client) { $client.Close() }
                }
            }
        })
        $httpTimer.Start()

        $form.Add_FormClosed({
            $httpTimer.Stop()
            $httpListener.Stop()
        })
    }
}

[System.Windows.Forms.Application]::Run($form)
