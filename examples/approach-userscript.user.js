// ==UserScript==
// @name         Cash drawer bridge for Approach.app
// @namespace    https://github.com/TitaniaAnn/cash-drawer-trigger
// @version      1.0
// @description  Kick the local USB cash drawer and print receipts on the receipt printer from Approach.app
// @match        https://approach.app/*
// @match        https://*.approach.app/*
// @grant        GM_xmlhttpRequest
// @grant        unsafeWindow
// @connect      localhost
// @connect      127.0.0.1
// @run-at       document-idle
// ==/UserScript==

/* Runs inside the browser on Approach.app pages (install with Tampermonkey or
   Violentmonkey). Talks to the local HTTP server that Open-CashDrawer.ps1
   runs. GM_xmlhttpRequest is used instead of fetch so the site's
   Content-Security-Policy and CORS rules can't block the localhost call. */

(function () {
  'use strict';

  // ========================== CONFIG =========================================

  const BRIDGE = 'http://localhost:8737';   // match $HttpPort in the PS script

  // Clicking any button/link whose visible text contains one of these
  // (case-insensitive) kicks the drawer. Put the exact wording Approach uses
  // on its cash-payment button here - right-click it > Inspect to check.
  const DRAWER_BUTTON_TEXTS = ['cash'];

  // And/or match buttons by CSS selector, for ones without stable text:
  const DRAWER_BUTTON_SELECTORS = [];   // e.g. ['[data-testid="pay-cash"]']

  // Intercept window.print(): instead of the browser's print dialog, grab
  // the receipt text off the page and send it to the receipt printer.
  const INTERCEPT_PRINT = true;

  // Where the receipt lives in the DOM when Approach prints. '' = whole
  // page, which usually drags nav/menus along - inspect the page at the
  // moment printing is triggered and put a tighter selector here.
  const RECEIPT_SELECTOR = '';

  // If the drawer app isn't running, fall back to the normal print dialog
  // so a receipt can still be produced somehow.
  const FALLBACK_TO_REAL_PRINT = true;

  // ========================== BRIDGE CALLS ===================================

  function post(path, body, done) {
    GM_xmlhttpRequest({
      method: 'POST',
      url: BRIDGE + path,
      data: body || '',
      timeout: 5000,
      onload: function (r) {
        let ok = false;
        try { ok = JSON.parse(r.responseText).ok === true; } catch (e) { }
        if (!ok) console.error('[cash-drawer] ' + path + ' failed:', r.responseText);
        if (done) done(ok);
      },
      onerror: function () {
        console.error('[cash-drawer] app not reachable at ' + BRIDGE +
          ' - is Open-CashDrawer.ps1 running?');
        if (done) done(false);
      },
      ontimeout: function () {
        console.error('[cash-drawer] request to ' + BRIDGE + path + ' timed out');
        if (done) done(false);
      },
    });
  }

  function openDrawer(done) { post('/open', '', done); }
  function printReceipt(text, done) { post('/print', text, done); }

  // ========================== DRAWER ON BUTTON CLICK =========================

  const textNeedles = DRAWER_BUTTON_TEXTS.map(function (t) { return t.toLowerCase(); });

  function isDrawerButton(target) {
    const btn = target.closest('button, [role="button"], a, input[type="button"], input[type="submit"]');
    if (!btn) return false;
    if (DRAWER_BUTTON_SELECTORS.some(function (sel) { return btn.matches(sel); })) return true;
    const label = (btn.innerText || btn.value || '').trim().toLowerCase();
    return label !== '' && textNeedles.some(function (t) { return label.includes(t); });
  }

  // Capture phase, so the kick still fires when Approach's own click handler
  // calls stopPropagation().
  document.addEventListener('click', function (e) {
    if (e.target instanceof Element && isDrawerButton(e.target)) {
      openDrawer();
    }
  }, true);

  // ========================== PRINT INTERCEPTION =============================
  // A print job that reaches Windows is already rendered page graphics, too
  // late to reformat. Here we're upstream of all that: replace the page's
  // print() with one that reads the receipt text out of the DOM and posts it
  // to the receipt printer.

  if (INTERCEPT_PRINT) {
    const pageWindow = (typeof unsafeWindow !== 'undefined') ? unsafeWindow : window;
    const realPrint = pageWindow.print.bind(pageWindow);

    pageWindow.print = function () {
      const root = (RECEIPT_SELECTOR && document.querySelector(RECEIPT_SELECTOR)) || document.body;
      const text = (root.innerText || '').replace(/\n{3,}/g, '\n\n').trim();
      if (!text) { realPrint(); return; }
      printReceipt(text, function (ok) {
        if (!ok && FALLBACK_TO_REAL_PRINT) realPrint();
      });
    };
  }
})();
