# notes-api

A small web API for notes, with a web page. An example of a Pastel web
service (see `docs/web.md`).

```
pastel run          # then open http://localhost:8080
pastel test
```

| | |
|---|---|
| `GET /api/notes` | all notes, newest first |
| `GET /api/notes/:id` | one note |
| `POST /api/notes` | `{"title": "...", "text": "..."}` → 201 and the note |
| `PUT /api/notes/:id` | change title and text |
| `DELETE /api/notes/:id` | 204 |
| `GET /health` | `{"status": "ok", ...}` for monitoring |

```sh
curl -s localhost:8080/api/notes -d '{"title": "Alışveriş", "text": "süt, ekmek"}'
curl -s localhost:8080/api/notes
```

The notes are saved in `data/notes.json` (under systemd: `/var/lib/notes-api`).
The port comes from `config.toml` or `NOTES_API_SERVER_PORT`.
