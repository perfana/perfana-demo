# Obsidian Local REST API reference

All calls require the header: `Authorization: Bearer {apiKey}`

## Endpoints

| Operation | Method | Path | Notes |
|---|---|---|---|
| Write / overwrite note | `PUT` | `/vault/{path}` | Raw Markdown body; creates folders automatically |
| Read note | `GET` | `/vault/{path}` | Returns raw Markdown |
| Append to note | `POST` | `/vault/{path}` | Appends content to existing note |
| List folder | `GET` | `/vault/{folder}/` | Trailing slash = directory listing |
| Simple search | `POST` | `/search/simple/` | Body: `{ "query": "...", "contextLength": 100 }` |

## Ports

- `27124` — HTTPS (default, self-signed cert → pass `-k` to curl)
- `27123` — HTTP (requires `"enableInsecureServer": true` in `data.json`)

## API key location

```
{vaultRoot}/.obsidian/plugins/obsidian-local-rest-api/data.json  →  $.apiKey
```

## URL encoding

Spaces in vault paths must be encoded as `%20`.

Example: `Performance Reports/my-run.md` → `Performance%20Reports/my-run.md`

## Write example (curl)

```bash
curl -s -X PUT \
  "http://localhost:27123/vault/Performance%20Reports/${TEST_RUN_ID}.md" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: text/markdown" \
  --data-binary "${REPORT_MARKDOWN}"
```

## Write example (JavaScript fetch)

```js
await fetch(`http://localhost:27123/vault/Performance%20Reports/${testRunId}.md`, {
  method: 'PUT',
  headers: {
    'Authorization': `Bearer ${apiKey}`,
    'Content-Type': 'text/markdown',
  },
  body: reportMarkdown,
});
```
