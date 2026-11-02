import { createHash } from "node:crypto";
import { parse } from "csv-parse/sync";

// Card statements carry no Product column, so their rows use this key.
export const NO_PRODUCT = "";

function toCents(text) {
  const value = Number(text || "0");
  if (!Number.isFinite(value)) throw new Error(`Bad amount: ${text}`);
  return Math.round(value * 100);
}

function toDate(text) {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(text ?? "");
  if (!match) throw new Error(`Bad date: ${text}`);
  return match.slice(1).join("-");
}

// Rows are ready once Revolut sets a completion date, and State, when present, agrees.
function isSettled(row) {
  if (!row["Completed Date"]) return false;
  return row.State === undefined || row.State === "COMPLETED";
}

export function parseStatement(csv) {
  const rows = parse(csv, { columns: true, bom: true, skip_empty_lines: true, trim: true });
  const seen = new Map();
  const transactions = [];
  let skipped = 0;

  for (const row of rows) {
    if (!isSettled(row)) {
      skipped += 1;
      continue;
    }
    const product = row.Product ?? NO_PRODUCT;
    // Revolut reports fees as positive charges on top of the amount.
    const amount = toCents(row.Amount) - toCents(row.Fee);
    const key = [product, row["Started Date"], amount, row.Description].join("|");
    // Identical rows in one export stay distinct, and keep their ids across exports.
    const count = (seen.get(key) ?? 0) + 1;
    seen.set(key, count);
    const hash = createHash("sha256").update(key).digest("hex").slice(0, 24);

    transactions.push({
      product,
      transaction: {
        date: toDate(row["Started Date"]),
        amount,
        payee_name: row.Description,
        imported_payee: row.Description,
        imported_id: `revolut-${hash}-${count}`,
        cleared: true,
      },
    });
  }

  return { transactions, skipped };
}

const SPENT = /You spent\s*\D?\s*([\d,]+(?:\.\d{1,2})?)/;

// Card notifications mention available credit; the rest come from the current account.
export function parseNotification({ title, text }) {
  const spent = SPENT.exec(text ?? "");
  if (!spent || !title) return null;
  return {
    payee: title.trim(),
    amount: -toCents(spent[1].replaceAll(",", "")),
    card: /available\s*credit/i.test(text),
  };
}

export function groupByAccount(transactions, accounts, defaultAccount) {
  const groups = new Map();
  const unknown = new Set();

  for (const { product, transaction } of transactions) {
    const account = product === NO_PRODUCT ? defaultAccount : accounts[product];
    if (!account) {
      unknown.add(product || "(no Product column)");
      continue;
    }
    if (!groups.has(account)) groups.set(account, []);
    groups.get(account).push(transaction);
  }

  if (unknown.size > 0) {
    throw new Error(`No account for products: ${[...unknown].join(", ")}`);
  }
  return groups;
}
