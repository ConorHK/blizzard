#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";
import { timingSafeEqual } from "node:crypto";
import * as api from "@actual-app/api";
import { groupByAccount, parseNotification, parseStatement } from "./revolut.js";

const MAX_BYTES = 5 * 1024 * 1024;
const SEEN_LIMIT = 1000;

const config = JSON.parse(readFileSync(process.argv[2], "utf8"));
const credential = (name) =>
  readFileSync(join(process.env.CREDENTIALS_DIRECTORY, name), "utf8").trim();
const token = Buffer.from(credential("token"));
const seenFile = join(config.dataDir, "notified.json");

async function withBudget(work) {
  await api.init({
    dataDir: config.dataDir,
    serverURL: config.serverURL,
    password: credential("actual-password"),
  });
  try {
    await api.downloadBudget(config.syncId);
    const ids = new Map((await api.getAccounts()).map((account) => [account.name, account.id]));
    const accountId = (name) => {
      if (!ids.has(name)) throw new Error(`No Actual account named ${name}`);
      return ids.get(name);
    };
    const result = await work(accountId);
    await api.sync();
    return result;
  } finally {
    await api.shutdown();
  }
}

async function importStatement(csv) {
  const { transactions, skipped } = parseStatement(csv);
  const groups = groupByAccount(transactions, config.accounts, config.defaultAccount);
  const result = { skipped, accounts: {} };
  if (groups.size === 0) return result;

  return withBudget(async (accountId) => {
    for (const [name, list] of groups) {
      const { added, updated, errors } = await api.importTransactions(accountId(name), list);
      if (errors?.length) throw new Error(errors.map((e) => e.message).join("; "));
      result.accounts[name] = { added: added.length, updated: updated.length };
    }
    return result;
  });
}

// Notification entries carry no imported_id, so the month's CSV import later matches and settles them.
async function addNotification({ id, title, text, date }) {
  const spend = parseNotification({ title, text });
  if (!spend || !/^\d{4}-\d{2}-\d{2}$/.test(date ?? "")) return { ignored: true };

  const seen = existsSync(seenFile) ? JSON.parse(readFileSync(seenFile, "utf8")) : [];
  if (seen.includes(id)) return { duplicate: true };

  await withBudget(async (accountId) => {
    await api.addTransactions(accountId(spend.card ? config.defaultAccount : config.spendAccount), [
      { date, amount: spend.amount, payee_name: spend.payee, cleared: false },
    ]);
  });
  writeFileSync(seenFile, JSON.stringify([...seen, id].slice(-SEEN_LIMIT)));
  return { added: spend };
}

function authorized(req) {
  const given = Buffer.from((req.headers.authorization ?? "").replace(/^Bearer /, ""));
  return given.length === token.length && timingSafeEqual(given, token);
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BYTES) throw new Error("File too large");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function reply(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

const routes = {
  "/import": (body) => importStatement(body),
  "/notify": (body) => addNotification(JSON.parse(body)),
};

// Actual's API holds one open budget per process, so requests run one at a time.
let queue = Promise.resolve();

const server = createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") return reply(res, 200, { ok: true });
  const route = req.method === "POST" && routes[req.url];
  if (!route) return reply(res, 404, { error: "Not found" });
  if (!authorized(req)) return reply(res, 401, { error: "Bad token" });

  try {
    const body = await readBody(req);
    const job = queue.then(() => route(body));
    queue = job.catch(() => {});
    const result = await job;
    console.log(req.url, JSON.stringify(result));
    reply(res, 200, result);
  } catch (error) {
    console.error(error);
    reply(res, 400, { error: error.message });
  }
});

server.listen(config.port, config.host, () => {
  console.log(`Listening on ${config.host}:${config.port}`);
});
