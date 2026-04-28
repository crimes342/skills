# 📋 每日新闻简报 | {{date}} {{weekday}}

## 🎰 Polymarket 专项
### 🚨 临近到期 + 异常信号
{{#each expiring_anomalies}}
**📌 {{title}}**
- 赔率：{{#each markets}}{{outcome}}: {{price}} {{/each}}
- 到期：{{endDate}} ({{hoursLeft}}h)
- 异常：{{#each signals}}{{detail}}; {{/each}}
- 💡 {{analysis}}
- 🔗 {{url}}
{{/each}}

## 📰 新闻简报
### 🌍 地缘时政 / 💰 财经市场 / 🔬 前沿科技 / 🤖 AI 动态
（每个领域 2-5 条，附原始 URL）

## 📌 今日看点
（3-5 句总结）
