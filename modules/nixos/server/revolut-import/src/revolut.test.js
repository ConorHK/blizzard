import assert from "node:assert/strict";
import { test } from "node:test";
import { groupByAccount, parseNotification, parseStatement } from "./revolut.js";

const card = `\ufeffType,Started Date,Completed Date,Description,Amount,Fee,Balance
CARD_PAYMENT,2026-10-01 12:30:00,2026-10-02 09:00:00,Tesco,-12.34,0.00,-12.34
CARD_PAYMENT,2026-10-03 08:00:00,,Pending Cafe,-3.00,0.00,-15.34
CARD_PAYMENT,2026-10-04 18:00:00,2026-10-05 09:00:00,"Shop, Ltd",-10.00,0.50,-25.84
REPAYMENT,2026-10-06 10:00:00,2026-10-06 10:00:00,Repayment,25.84,0.00,0.00
`;

const current = `Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
TOPUP,Current,2026-10-01 10:00:00,2026-10-01 10:00:00,Salary,1000.00,0.00,GBP,COMPLETED,1000.00
CARD_PAYMENT,Current,2026-10-02 10:00:00,2026-10-02 10:00:00,Reverted,-5.00,0.00,GBP,REVERTED,1000.00
TRANSFER,Savings,2026-10-03 10:00:00,2026-10-03 10:00:00,To pot,100.00,0.00,GBP,COMPLETED,100.00
`;

test("card statement skips pending rows and nets fees", () => {
  const { transactions, skipped } = parseStatement(card);
  assert.equal(skipped, 1);
  assert.deepEqual(
    transactions.map(({ transaction }) => [transaction.date, transaction.amount, transaction.payee_name]),
    [
      ["2026-10-01", -1234, "Tesco"],
      ["2026-10-04", -1050, "Shop, Ltd"],
      ["2026-10-06", 2584, "Repayment"],
    ],
  );
});

test("imported ids are stable across overlapping exports", () => {
  const full = parseStatement(card).transactions.map(({ transaction }) => transaction.imported_id);
  const tail = card.split("\n").filter((_, i) => i !== 1).join("\n");
  const partial = parseStatement(tail).transactions.map(({ transaction }) => transaction.imported_id);
  assert.deepEqual(partial, full.slice(1));
});

test("identical rows get distinct ids", () => {
  const row = "CARD_PAYMENT,2026-10-01 12:30:00,2026-10-02 09:00:00,Bus,-1.75,0.00,-1.75";
  const csv = `Type,Started Date,Completed Date,Description,Amount,Fee,Balance\n${row}\n${row}\n`;
  const [a, b] = parseStatement(csv).transactions.map(({ transaction }) => transaction.imported_id);
  assert.notEqual(a, b);
});

test("State column drops non-completed rows", () => {
  const { transactions, skipped } = parseStatement(current);
  assert.equal(skipped, 1);
  assert.deepEqual(
    transactions.map(({ product }) => product),
    ["Current", "Savings"],
  );
});

test("rows route by product, card rows to the default", () => {
  const rows = [...parseStatement(current).transactions, ...parseStatement(card).transactions];
  const groups = groupByAccount(rows, { Current: "Revolut", Savings: "Pots" }, "Revolut Card");
  assert.deepEqual(
    [...groups].map(([account, list]) => [account, list.length]),
    [
      ["Revolut", 1],
      ["Pots", 1],
      ["Revolut Card", 3],
    ],
  );
});

test("card notifications parse payee and amount", () => {
  assert.deepEqual(
    parseNotification({ title: "Lidl", text: "\u{1F6D2} You spent \u20AC25\nAvailableCredit \u20AC9,877.05" }),
    { payee: "Lidl", amount: -2500, card: true },
  );
  assert.deepEqual(
    parseNotification({
      title: "The Grafton Barber",
      text: "\u2764\uFE0F You spent \u20AC1,033.50\nAvailable credit: \u20AC8,846.65",
    }),
    { payee: "The Grafton Barber", amount: -103350, card: true },
  );
});

test("spends without available credit are not card spends", () => {
  assert.deepEqual(parseNotification({ title: "Lidl", text: "You spent \u20AC25\nBalance \u20AC100" }), {
    payee: "Lidl",
    amount: -2500,
    card: false,
  });
});

test("other notifications are ignored", () => {
  assert.equal(parseNotification({ title: "Revolut", text: "Your statement is ready" }), null);
});

test("unmapped products fail loudly", () => {
  const { transactions } = parseStatement(current);
  assert.throws(() => groupByAccount(transactions, { Current: "Revolut" }, "Card"), /Savings/);
});
