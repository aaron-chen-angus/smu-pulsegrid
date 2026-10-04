/**
 * PULSE//GRID — Phase 2 Google Sheets backend (design §3.9, R9.2)
 *
 * Receives one session as a JSON bundle and appends rows to three tabs:
 *   Sessions, EmotionScans, IntensityTimeline.
 *
 * Transport contract (must match the client in index.html / config.js):
 *  - The client POSTs with Content-Type: text/plain to avoid the CORS preflight
 *    that Apps Script web apps cannot answer. So read the body from e.postData.contents.
 *  - Every request carries a shared "token" that must equal SHEET_TOKEN below.
 *
 * Deploy:  Extensions is not used — this is a standalone script bound to the Sheet.
 *   1. In the Sheet: Extensions > Apps Script. Paste this file as Code.gs.
 *   2. Set SHEET_TOKEN to a long random string (also put it in config.js sheets.token).
 *   3. Deploy > New deployment > type "Web app".
 *        Execute as: Me
 *        Who has access: Anyone
 *   4. Copy the Web app URL into config.js sheets.url.
 *
 * The payload shape (from PULSE.record.toBundle) is:
 *   { token, sessions:[{...}], emotionScans:[{...}], intensityTimeline:[{...}] }
 */

var SHEET_TOKEN = 'smupg-7h3Qx9K2mNp4';

// Column order per tab (must match §3.9 and the client's record builders).
var COLS = {
  Sessions: [
    'session_id','name','matched_bank','match_distance','routine_id',
    'sign_in_at','start_at','end_at','sign_out_at','duration_s','completed',
    'signout_override','active_pct','kcal','met_mean','upper_avg','upper_peak',
    'upper_effort_pct','lower_avg','lower_peak','lower_effort_pct','overall_avg',
    'match_pct','sync_score','zone_pct','weight_kg','weight_defaulted','app_version'
  ],
  EmotionScans: [
    'session_id','name','phase','scanned_at','frames','neutral','happy','sad',
    'angry','fearful','disgusted','surprised','dominant','valence','arousal',
    'neg_affect','stress_level','stress_driver'
  ],
  IntensityTimeline: [
    'session_id','t_s','user_upper','user_lower','user_overall',
    'ref_upper','ref_lower','ref_overall','match_pct'
  ]
};

function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return json({ ok: false, error: 'no body' });
    }
    var payload = JSON.parse(e.postData.contents);

    if (!payload || payload.token !== SHEET_TOKEN) {
      return json({ ok: false, error: 'bad token' });
    }

    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var written = {};
    written.Sessions = appendRows(ss, 'Sessions', payload.sessions);
    written.EmotionScans = appendRows(ss, 'EmotionScans', payload.emotionScans);
    written.IntensityTimeline = appendRows(ss, 'IntensityTimeline', payload.intensityTimeline);

    return json({ ok: true, written: written });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

// Simple GET so you can sanity-check the deployment URL in a browser.
function doGet() {
  return json({ ok: true, service: 'pulsegrid', tabs: Object.keys(COLS) });
}

function appendRows(ss, tabName, rows) {
  if (!rows || !rows.length) return 0;
  var sheet = ss.getSheetByName(tabName);
  if (!sheet) {
    sheet = ss.insertSheet(tabName);
    sheet.appendRow(COLS[tabName]);     // write header on first use
  }
  // Ensure a header exists even if the tab was pre-created empty.
  if (sheet.getLastRow() === 0) sheet.appendRow(COLS[tabName]);

  var cols = COLS[tabName];
  var matrix = rows.map(function (r) {
    return cols.map(function (c) {
      var v = r[c];
      return (v === undefined || v === null) ? '' : v;
    });
  });
  sheet.getRange(sheet.getLastRow() + 1, 1, matrix.length, cols.length).setValues(matrix);
  return matrix.length;
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
