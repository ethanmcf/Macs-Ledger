/**
 * Mac's Ledger: Google Sheet backup.
 *
 * SETUP (once)
 *  1. Create a Google Sheet. Extensions › Apps Script. Replace the contents of Code.gs with this file. Save.
 *  2. Project Settings (gear) › Script Properties › Add property: TOKEN = a long random secret you make up.
 *  3. Deploy › New deployment › type "Web app". Execute as: Me. Who has access: Anyone. Deploy, and authorize.
 *  4. Copy the Web app URL. In the app: Settings › Backup to Google Sheet › paste the URL and the same TOKEN.
 *  5. Tap "Back Up Everything".
 * After editing this script later: Deploy › Manage deployments › edit › Version: New version (the URL stays the same).
 *
 * HOW IT WORKS
 *  - POST {token, changes:[…]}: the app sends changes. Each row is matched by id. The newer updatedAt wins.
 *    Deletes set deleted = TRUE (rows are never removed), so a later "Update from Google Sheet" knows about them.
 *  - GET ?action=export&token=…: returns every row as JSON, for "Update from Google Sheet".
 *  - onEdit: when you edit a row by hand, updatedAt is stamped (so your edit wins in the app) and new rows get an id.
 *
 * Don't reorder or rename the columns. You can add your own columns to the right, or extra tabs (e.g. summaries).
 * To delete a transaction from the sheet, type TRUE in its deleted column instead of deleting the row.
 */

const TABS = {
  expense: {
    name: 'Transactions',
    cols: ['id', 'date', 'category', 'amount', 'note', 'categoryId', 'updatedAt', 'deleted'],
  },
  category: {
    name: 'Categories',
    cols: ['id', 'name', 'icon', 'sortOrder', 'hidden', 'updatedAt', 'deleted'],
  },
};
// Columns kept as plain text so Sheets doesn't reformat them.
const TEXT_COLS = ['id', 'categoryId', 'updatedAt'];

// ---------------------------------------------------------------- web app

function doPost(e) {
  let body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return json({ ok: false, error: 'Request body is not JSON.' });
  }
  if (!validToken(body.token)) return json({ ok: false, error: 'Wrong token. Check Settings › Backup in the app.' });

  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const changes = Array.isArray(body.changes) ? body.changes : [];
    let applied = 0;
    // Categories first, so a batch that adds a category and its expenses lands in order.
    for (const kind of ['category', 'expense']) {
      applied += applyChanges(TABS[kind], changes.filter(c => c.kind === kind));
    }
    return json({ ok: true, applied: applied });
  } catch (err) {
    return json({ ok: false, error: 'Sheet error: ' + err.message });
  } finally {
    lock.releaseLock();
  }
}

function doGet(e) {
  const params = (e && e.parameter) || {};
  if (!validToken(params.token)) return json({ ok: false, error: 'Wrong token. Check Settings › Backup in the app.' });
  if (params.action !== 'export') return json({ ok: false, error: 'Unknown action.' });

  const tz = SpreadsheetApp.getActive().getSpreadsheetTimeZone();
  return json({
    ok: true,
    categories: readRows(TABS.category).map(r => ({
      id: String(r.id),
      name: String(r.name),
      icon: String(r.icon || 'tag.fill'),
      sortOrder: Number(r.sortOrder) || 0,
      hidden: isTrue(r.hidden),
      updatedAt: timestamp(r.updatedAt),
      deleted: isTrue(r.deleted),
    })),
    expenses: readRows(TABS.expense).map(r => ({
      id: String(r.id),
      date: r.date instanceof Date ? Utilities.formatDate(r.date, tz, 'yyyy-MM-dd') : String(r.date),
      category: String(r.category),
      categoryId: r.categoryId ? String(r.categoryId) : null,
      amount: (Math.round(Number(r.amount) * 100) / 100).toFixed(2),
      note: String(r.note || ''),
      updatedAt: timestamp(r.updatedAt),
      deleted: isTrue(r.deleted),
    })),
  });
}

// ---------------------------------------------------------------- hand edits

/** Simple trigger: runs when you edit the sheet by hand (not when the app writes). */
function onEdit(e) {
  const sheet = e.range.getSheet();
  const tab = Object.values(TABS).find(t => t.name === sheet.getName());
  if (!tab) return;

  const idCol = tab.cols.indexOf('id') + 1;
  const updatedCol = tab.cols.indexOf('updatedAt') + 1;
  const categoryIdCol = tab.cols.indexOf('categoryId') + 1; // 0 on the Categories tab
  const categoryCol = tab.cols.indexOf('category') + 1;
  const firstCol = e.range.getColumn();
  const lastCol = firstCol + e.range.getNumColumns() - 1;
  // Ignore edits to the bookkeeping columns themselves.
  if (firstCol === lastCol && (firstCol === idCol || firstCol === updatedCol)) return;

  const now = new Date().toISOString();
  for (let row = Math.max(2, e.range.getRow()); row <= e.range.getLastRow(); row++) {
    const values = sheet.getRange(row, 1, 1, tab.cols.length).getValues()[0];
    if (values.every(v => v === '' || v === null)) continue;
    if (!values[idCol - 1]) sheet.getRange(row, idCol).setValue(Utilities.getUuid().toUpperCase());
    sheet.getRange(row, updatedCol).setValue(now);
    // Typing a different category name by hand: drop the old link so the app matches by name.
    if (categoryIdCol > 0 && firstCol <= categoryCol && categoryCol <= lastCol) {
      sheet.getRange(row, categoryIdCol).setValue('');
    }
  }
}

// ---------------------------------------------------------------- helpers

function applyChanges(tab, changes) {
  if (changes.length === 0) return 0;
  const sheet = getSheet(tab);
  const width = Math.max(tab.cols.length, sheet.getLastColumn());
  const lastRow = sheet.getLastRow();
  const rows = lastRow > 1 ? sheet.getRange(2, 1, lastRow - 1, width).getValues() : [];
  const updatedIdx = tab.cols.indexOf('updatedAt');
  const deletedIdx = tab.cols.indexOf('deleted');

  const index = new Map();
  rows.forEach((row, i) => { if (row[0]) index.set(String(row[0]).toUpperCase(), i); });

  const touched = new Set();
  let applied = 0;
  for (const change of changes) {
    const id = String(change.id).toUpperCase();
    const incoming = Date.parse(change.updatedAt) || 0;
    let i = index.get(id);

    if (i !== undefined) {
      const existing = Date.parse(timestamp(rows[i][updatedIdx])) || 0;
      if (incoming < existing) continue; // the sheet has a newer hand edit; keep it
      if (change.op === 'delete') {
        rows[i][deletedIdx] = true;
        rows[i][updatedIdx] = change.updatedAt;
      } else {
        rows[i] = pad(toRow(tab, change), width, rows[i]);
      }
    } else {
      if (change.op === 'delete') continue; // never reached the sheet; nothing to mark
      rows.push(pad(toRow(tab, change), width));
      i = rows.length - 1;
      index.set(id, i);
    }
    touched.add(i);
    applied++;
  }

  if (touched.size > 0 && rows.length > 0) {
    ensureRows(sheet, tab, rows.length + 1);
    sheet.getRange(2, 1, rows.length, width).setValues(rows);
  }
  return applied;
}

/** New tabs start with 1,000 rows; writing past the end throws, so grow the tab first. */
function ensureRows(sheet, tab, needed) {
  const max = sheet.getMaxRows();
  if (needed <= max) return;
  const extra = needed - max + 500;
  sheet.insertRowsAfter(max, extra);
  formatColumns(sheet, tab, max + 1, extra);
}

function toRow(tab, c) {
  if (tab === TABS.expense) {
    return [c.id, c.date, c.category || '', Number(c.amount), c.note || '', c.categoryId || '', c.updatedAt, false];
  }
  return [c.id, c.name, c.icon, Number(c.sortOrder) || 0, !!c.hidden, c.updatedAt, false];
}

/** Pads a row to the sheet's width, keeping any extra columns you added on the right. */
function pad(row, width, existing) {
  const out = row.slice();
  for (let i = out.length; i < width; i++) out.push(existing ? existing[i] : '');
  return out;
}

function getSheet(tab) {
  const book = SpreadsheetApp.getActive();
  let sheet = book.getSheetByName(tab.name);
  if (!sheet) {
    sheet = book.insertSheet(tab.name);
    sheet.getRange(1, 1, 1, tab.cols.length).setValues([tab.cols]).setFontWeight('bold');
    sheet.setFrozenRows(1);
    formatColumns(sheet, tab, 2, sheet.getMaxRows() - 1);
  }
  return sheet;
}

function formatColumns(sheet, tab, firstRow, count) {
  TEXT_COLS.forEach(name => {
    const col = tab.cols.indexOf(name) + 1;
    if (col > 0) sheet.getRange(firstRow, col, count, 1).setNumberFormat('@');
  });
  if (tab === TABS.expense) {
    sheet.getRange(firstRow, 2, count, 1).setNumberFormat('yyyy-mm-dd');
    sheet.getRange(firstRow, 4, count, 1).setNumberFormat('$#,##0.00');
  }
}

function readRows(tab) {
  const sheet = getSheet(tab);
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];
  return sheet.getRange(2, 1, lastRow - 1, tab.cols.length).getValues()
    .filter(row => row[0])
    .map(row => Object.fromEntries(tab.cols.map((name, i) => [name, row[i]])));
}

function validToken(token) {
  const expected = PropertiesService.getScriptProperties().getProperty('TOKEN');
  return !!expected && token === expected;
}

function timestamp(value) {
  if (value instanceof Date) return value.toISOString();
  return value ? String(value) : '1970-01-01T00:00:00.000Z';
}

function isTrue(value) {
  return value === true || String(value).toUpperCase() === 'TRUE';
}

function json(object) {
  return ContentService.createTextOutput(JSON.stringify(object)).setMimeType(ContentService.MimeType.JSON);
}
