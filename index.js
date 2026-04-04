require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const sqlite3 = require('sqlite3').verbose();
const app = express();
app.use(bodyParser.json());

const db = new sqlite3.Database('livros.db');

db.serialize(() => {
  db.run(`CREATE TABLE IF NOT EXISTS livros (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    titulo TEXT,
    autor TEXT,
    ano INTEGER,
    segredo TEXT
  )`);
});

app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok' });
});


app.get('/livros', (req, res) => {
  db.all('SELECT * FROM livros', [], (err, rows) => {
    if (err) return res.status(500).json({ erro: err.message });
    res.json(rows);
  });
});


app.get('/livros/:id', (req, res) => {
  db.get('SELECT * FROM livros WHERE id = ?', [req.params.id], (err, row) => {
    if (err) return res.status(500).json({ erro: err.message });
    res.json(row);
  });
});


app.post('/livros', (req, res) => {
  const { titulo, autor, ano, segredo } = req.body;

  db.run('INSERT INTO livros (titulo, autor, ano, segredo) VALUES (?, ?, ?, ?)', 
    [titulo, autor, ano, segredo],
    function (err) {
      if (err) return res.status(500).json({ erro: err.message });      
      db.get('SELECT * FROM livros WHERE id = ?', [this.lastID], (err, row) => {
        if (err) return res.status(500).json({ erro: err.message });
        res.status(201).json(row);
      });
    }
  );
});


app.put('/livros/:id', (req, res) => {
  const { titulo, autor, ano, segredo } = req.body;
  db.run('UPDATE livros SET titulo = ?, autor = ?, ano = ?, segredo = ? WHERE id = ?',
    [titulo, autor, ano, segredo, req.params.id],
    function (err) {
      if (err) return res.status(500).json({ erro: err.message });
      db.get('SELECT * FROM livros WHERE id = ?', [req.params.id], (err, row) => {
        if (err) return res.status(500).json({ erro: err.message });
        res.json(row);
      });
    }
  );
});


app.delete('/livros/:id', (req, res) => {
  db.run('DELETE FROM livros WHERE id = ?', [req.params.id], function (err) {
    if (err) return res.status(500).json({ erro: err.message });
    res.status(204).send();
  });
});


app.get('/segredo', (req, res) => {
  res.send(process.env.SEGREDO_SUPERSECRETO || 'sem segredo');
});


app.get('/xss', (req, res) => {
  const nome = req.query.nome || '';
  res.send(`<h1>Olá, ${nome}</h1>`);
});


app.get('/sql', (req, res) => {
  const query = req.query.q;
  db.all(`SELECT * FROM livros WHERE titulo = '${query}'`, [], (err, rows) => {
    if (err) return res.status(500).json({ erro: err.message });
    res.send(`Executando consulta: SELECT * FROM livros WHERE titulo = '${query}'<br>Resultado: ${JSON.stringify(rows)}`);
  });
});


const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Servidor rodando na porta ${PORT}`);
});
