# cash-drawer-trigger

An always-on-top button for Windows 11 that pops open a USB cash drawer. One
PowerShell script, no installs — uses the WinForms and Win32 APIs already on
every Windows machine.

## Quick start

1. Clone or download this repo.
2. Open `Open-CashDrawer.ps1` in any editor and fill in the CONFIG block at the
   top (see below).
3. Double-click `OpenCashDrawer.bat`.

A small green button appears in the bottom-right corner. Click it to kick the
drawer. Drag it anywhere; right-click → Exit to close it. It flashes brighter
green on success and red (with the error message) on failure.

## Configuring for your drawer

How you trigger the drawer depends on how it's plugged in.

### Drawer plugged into a receipt printer (most common)

The drawer's RJ11/RJ12 cable goes into the "DK" port on an Epson, Star,
Bixolon, etc. receipt printer, and the printer is what's on USB. Set:

```powershell
$Mode = 'Printer'
$PrinterName = 'EPSON TM-T20III Receipt'   # your exact printer name
```

The printer name must match what Windows shows in **Settings → Bluetooth &
devices → Printers & scanners** exactly. Or list them from PowerShell:

```powershell
Get-Printer | Select-Object Name
```

The default kick command (`ESC p 0 25 250`) works on Epson and nearly every
ESC/POS-compatible printer. Star printers running in Star line mode use a
single `BEL` byte instead — change the bytes line to:

```powershell
[byte[]]$KickBytes = 0x07
```

If the drawer is on pin 2 of the printer (rare, dual-drawer setups), change
the third byte from `0x00` to `0x01`.

### Drawer connected directly over USB

Drawers like the APG USBPro or ones using a Star SMD2 interface show up as a
serial (COM) port. Check **Device Manager → Ports (COM & LPT)** for the port
number, then set:

```powershell
$Mode = 'COM'
$ComPort = 'COM3'
```

Most serial drawers open on receiving any bytes; the default kick bytes work.
APG USBPro units are usually configured to open on the character `a`:

```powershell
[byte[]]$ComKickBytes = 0x61
```

If your drawer is USB HID instead (no COM port appears), it needs
vendor-specific software or an OPOS driver — this script can't reach it
directly. Most vendors (APG, MMF) offer a virtual-COM mode or driver that
makes it appear as a COM port; enable that and use COM mode.

## Running it at logon

Put a shortcut to `OpenCashDrawer.bat` in the Startup folder: press
`Win+R`, run `shell:startup`, and drop the shortcut there.

## Troubleshooting

- **Red ERROR flash, "Printer not found"** — the name in `$PrinterName`
  doesn't match. Copy it verbatim from `Get-Printer`.
- **Job prints garbage or nothing, drawer stays shut** — the printer driver
  isn't passing RAW data or the printer isn't ESC/POS. Try the Star `0x07`
  byte, or install the manufacturer's native driver instead of a generic one.
- **Drawer clicks but doesn't open** — pulse too short. Raise the fourth byte
  (on-time): `0x1B, 0x70, 0x00, 0x32, 0xFA` gives a 100 ms pulse.
- **"Access to the port 'COM3' is denied"** — something else (POS software,
  vendor utility) has the port open. Close it, or use printer mode.
