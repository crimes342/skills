# daily-news skill

Generates a daily briefing that combines:

- Polymarket market‑scan (anomalies, expiring contracts, hot topics)  
- Web‑search‑based news rounds for Geopolitics, Finance, Edge Tech, AI  
- A formatted report ready to post in chat or send via cron

## Usage

In any Hermes conversation say:

```
每日新闻
```
or
```
daily news
```

The skill will run the Polymarket scanner (Node.js ≥ 18), perform four web searches, and compose a structured briefing.

## License

MIT – see the `LICENSE` file for details.