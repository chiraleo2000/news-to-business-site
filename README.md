# News to Business

One GitHub Pages site with tabs for every daily news topic:

| Tab | Source path |
|---|---|
| AI News | `Documents\ai-news` |
| Gov News | `Documents\Gov-News-GitHub\gov-news-thailand` (+ github-pages / Document fallback) |
| Police | `Documents\police-news-intel-kit\github-pages\data` |
| Tech Law | `Documents\tech-law-thailand\data` |

## Local layout

```
news-to-business-site/
  index.html              # multi-topic news tabs
  police-intel.html       # Police GraphRAG + chatbot + connect
  assets/css/site.css
  assets/css/police-brain.css
  js/app.js
  js/police/{graph,rag,positions,format,boot}.js
  data/feed.json          # unified feed rebuilt by sync
  data/{ai,gov,police,tech-law}/
  data/police/graph.json  # GraphRAG
  data/police/tunnel.json # LLM HTTPS tunnel for chat
  sources.json
  Sync-FromSources.ps1
  DailyPush.ps1
  Register-DailyPushSchedule.ps1
  PUSH.bat
```

## Police GraphRAG / chat

- Live: `https://chiraleo2000.github.io/news-to-business-site/police-intel.html`
- Main site tab **ข่าวอาชญากรรมไซเบอร์** shows cyber news cards (no separate cyber graph).
- Chat uses in-browser GraphRAG + Gemma via `data/police/tunnel.json` (same as police-news-intel-kit).
- If the tunnel expires, open **เชื่อมต่อ LLM** and paste a fresh `https://….ngrok-free.app` base.

## Daily automation

1. `Sync-FromSources.ps1` copies newest JSON from the topic repos (default last 60 days) and rebuilds `data/feed.json`.
2. `PUSH.bat` commits changed site/data files and pushes to GitHub Pages.
3. `DailyPush.ps1` waits for AI/Gov/Police source files, syncs, then pushes.
4. Task Scheduler:
   - **18:45** `News-to-Business-DailyPush` (after AI/Gov 18:00)
   - **20:30** `News-to-Business-RetryPush -Retry` (after Gov-Retry 20:00)

Register the Windows tasks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Register-DailyPushSchedule.ps1
```

Manual run (sync + push):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DailyPush.ps1
```

Sync only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\DailyPush.ps1 -SkipPush
```

## GitHub Pages

Repo: `chiraleo2000/news-to-business-site`  
Branch: `main` / root (or `docs` if configured). Enable Pages from the repo Settings after first push.
