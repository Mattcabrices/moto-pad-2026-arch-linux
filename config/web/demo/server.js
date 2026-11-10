// Moto Pad (archpad) website starter: Express API over SQLite (Node's built-in node:sqlite, no database server).
// Caddy serves the React build and sends /api/* here. Data lives in data/site.db (back it up like any file).
// (PostgreSQL and MongoDB cannot run on this kernel: it has no System V shared memory.)
import express from 'express';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const port = Number(process.env.PORT || 3000);
const file = process.env.DB_FILE || 'data/site.db';
fs.mkdirSync(path.dirname(file), { recursive: true });
const db = new DatabaseSync(file);
db.exec(`PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS notes (
    id INTEGER PRIMARY KEY,
    text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 500),
    created TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')))`);
const q = {
  list: db.prepare('SELECT id, text, created FROM notes ORDER BY id DESC LIMIT 100'),
  add: db.prepare('INSERT INTO notes (text) VALUES (?) RETURNING id, text, created'),
  del: db.prepare('DELETE FROM notes WHERE id = ?'),
  version: db.prepare('SELECT sqlite_version() AS v'),
};

const app = express();
app.use(express.json({ limit: '16kb' }));

app.get('/api/health', (_req, res) => {
  res.json({ ok: true, host: os.hostname(), uptime: os.uptime(), node: process.version, db: `SQLite ${q.version.get().v}` });
});

app.get('/api/notes', (_req, res) => res.json(q.list.all()));

app.post('/api/notes', (req, res) => {
  const text = String(req.body?.text ?? '').trim().slice(0, 500);
  if (!text) return res.status(400).json({ error: 'text is required' });
  res.status(201).json(q.add.get(text));
});

app.delete('/api/notes/:id', (req, res) => {
  if (!/^\d+$/.test(req.params.id)) return res.status(400).json({ error: 'bad id' });
  q.del.run(Number(req.params.id));
  res.status(204).end();
});

app.listen(port, '127.0.0.1', () => console.log(`archpad web app on 127.0.0.1:${port}`));
