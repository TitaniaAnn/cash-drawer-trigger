// website-trigger.js
// Drop this into your site to open the cash drawer from the browser.
// Requires Open-CashDrawer.ps1 running on the same machine as the browser,
// with $EnableHttpTrigger = $true (the default).

const DRAWER_URL = 'http://localhost:8737/open'; // match $HttpPort in the script

async function openCashDrawer() {
  try {
    const res = await fetch(DRAWER_URL, { method: 'POST' });
    const data = await res.json();
    if (!data.ok) {
      console.error('Cash drawer error:', data.error);
    }
    return data.ok;
  } catch (err) {
    // Most likely: the button app isn't running on this machine.
    console.error('Cash drawer app not reachable:', err);
    return false;
  }
}

// Option 1 - wire specific buttons by id/selector:
//
//   document.querySelector('#checkout-cash').addEventListener('click', openCashDrawer);

// Option 2 - declarative: any element with a data-open-drawer attribute
// triggers the drawer, including elements added to the page later.
//
//   <button data-open-drawer>Cash Payment</button>
document.addEventListener('click', (e) => {
  if (e.target.closest('[data-open-drawer]')) {
    openCashDrawer();
  }
});
