import { StrictMode, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

function App() {
  const [health, setHealth] = useState(null);
  const [notes, setNotes] = useState([]);
  const [text, setText] = useState('');

  const load = () => fetch('/api/notes').then((r) => r.json()).then(setNotes);
  useEffect(() => {
    fetch('/api/health').then((r) => r.json()).then(setHealth).catch(() => setHealth({ ok: false }));
    load();
  }, []);

  async function add(e) {
    e.preventDefault();
    if (!text.trim()) return;
    await fetch('/api/notes', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text }) });
    setText('');
    load();
  }
  async function remove(id) {
    await fetch(`/api/notes/${id}`, { method: 'DELETE' });
    load();
  }

  return (
    <main>
      <h1>Served from a Moto Pad</h1>
      <p className="status">
        {health === null ? 'Checking…' : health.ok
          ? `${health.db} · Node ${health.node} · ${health.host}, up ${Math.round(health.uptime / 3600)} h`
          : 'API or database not reachable'}
      </p>
      <form onSubmit={add}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder="Write a note" maxLength={500} />
        <button>Add</button>
      </form>
      <ul>
        {notes.map((n) => (
          <li key={n.id}>
            <span>{n.text}</span>
            <button className="del" onClick={() => remove(n.id)} aria-label="Delete">×</button>
          </li>
        ))}
      </ul>
    </main>
  );
}

createRoot(document.getElementById('root')).render(<StrictMode><App /></StrictMode>);
