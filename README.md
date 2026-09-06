# cash-drawer-trigger

An always-on-top button for Windows 11 that pops open a USB cash drawer. One
PowerShell script, no installs — uses the WinForms and Win32 APIs already on
every Windows machine. It can also be triggered from JavaScript on a web page
(see [Triggering from a website](#triggering-from-a-website)).

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

## Triggering from a website

The app also runs a tiny HTTP server on `http://localhost:8737` (loopback
only — nothing off the machine can reach it), so JavaScript on any web page
open in a browser **on the same till PC** can pop the drawer:

```js
fetch('http://localhost:8737/open', { method: 'POST' });
```

`examples/website-trigger.js` is a drop-in version with error handling and
two wiring styles: attach to specific buttons by selector, or add a
`data-open-drawer` attribute to any element (a delegated listener catches
those, including ones added to the page later):

```html
<button data-open-drawer>Cash Payment</button>
<script src="website-trigger.js"></script>
```

To try it without a website, start the app and open
`examples/test-page.html` in a browser.

Config lives in the same CONFIG block as everything else:

```powershell
$EnableHttpTrigger = $true    # $false turns the server off entirely
$HttpPort          = 8737     # change if something else uses this port
$AllowedOrigin     = '*'      # CORS: lock to your site, e.g. 'https://pos.example.com'
```

Notes:

- The page can be served from anywhere (an https site included) — browsers
  treat `localhost` as trustworthy, so Chrome, Edge and Firefox allow the
  call from https pages. The app answers Chromium's Private Network Access
  preflight, which those requests go through.
- Setting `$AllowedOrigin` to your site's origin stops other websites open
  in the browser from reading the response. Worst case with `*` is that a
  malicious page could pop the drawer open, so tighten it if the till
  browses the open web.
- Success returns `{"ok":true}`; failures return `{"ok":false,"error":"..."}`
  with HTTP 500 and flash the on-screen button red, same as a failed click.

## Running it at startup

Easiest: the Startup folder. Runs whenever you log in.

1. Press `Win+R`, type `shell:startup`, press Enter — an Explorer window
   opens on your Startup folder.
2. Right-click `OpenCashDrawer.bat` → **Show more options** → **Create
   shortcut** (Windows won't create it inside the Startup folder directly,
   so make it next to the file first).
3. Move the new shortcut into the Startup folder from step 1.
4. Sign out and back in to confirm the button appears on its own.

If you want it for every user of the till, use the all-users folder
instead: `shell:common startup` (needs admin to write there).

Alternative: Task Scheduler, useful if the button comes up before the
printer is ready and errors — you can add a delay.

1. Open **Task Scheduler** → **Create Basic Task**.
2. Name it "Cash drawer button", trigger **When I log on**.
3. Action **Start a program**, program:
   `C:\path\to\OpenCashDrawer.bat`.
4. After creating it, open the task's **Properties → Triggers → Edit** and
   tick **Delay task for: 30 seconds** if you need the printer/USB stack up
   first. On the **Conditions** tab, untick "Start the task only if the
   computer is on AC power" for laptops.

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
