# NotebookLM 技能

## 概述
通过 notebooklm-py CLI 操作 Google NotebookLM 的全部功能。

## 依赖
- google-auth skill（提供 Google 认证）
- notebooklm-py CLI（win4r fork v0.3.4-hermes.4）

## 认证前置
首次使用前必须通过 google-auth skill 完成 Google 登录。
认证状态存储在 `~/.notebooklm/profiles/default/storage_state.json`。

## CLI 命令参考

### 笔记本管理
```bash
notebooklm create "笔记本标题"          # 创建笔记本
notebooklm list                         # 列出所有笔记本
notebooklm use <notebook_id>            # 切换到指定笔记本
notebooklm status                       # 查看当前状态
notebooklm delete <notebook_id>         # 删除笔记本（需确认）
```

### 来源管理
```bash
notebooklm source add "https://..."     # 添加 URL 来源
notebooklm source add ./file.pdf        # 添加文件来源
notebooklm source add "https://youtube.com/..."  # 添加 YouTube
notebooklm source list                  # 列出所有来源
notebooklm source add-research "AI"     # 启动 Web Research 自动搜索
```

### 对话问答
```bash
notebooklm ask "关键主题是什么？"        # 基于来源问答
notebooklm ask "总结要点" --persona "资深分析师"  # 带角色的问答
notebooklm history                      # 查看对话历史
```

### 内容生成
```bash
# 播客（Audio Overview）
notebooklm generate audio "制作技术播客" --format deep-dive --language zh --wait
notebooklm generate audio --format brief --wait

# 视频
notebooklm generate video --style whiteboard --wait
notebooklm generate cinematic-video "纪录片风格" --wait

# 幻灯片
notebooklm generate slide-deck --wait

# 测验
notebooklm generate quiz --difficulty hard --wait

# 闪卡
notebooklm generate flashcards --quantity more --wait

# 信息图
notebooklm generate infographic --orientation portrait --wait

# 思维导图
notebooklm generate mind-map --wait

# 数据表
notebooklm generate data-table "比较关键概念" --wait

# 报告
notebooklm generate report --format study-guide --wait
```

### 下载
```bash
notebooklm download audio ./podcast.mp3
notebooklm download video ./overview.mp4
notebooklm download slide-deck ./slides.pdf
notebooklm download quiz --format json ./quiz.json
notebooklm download flashcards --format markdown ./cards.md
notebooklm download infographic ./infographic.png
notebooklm download mind-map ./mindmap.json
notebooklm download data-table ./data.csv
```

### 语言设置
```bash
notebooklm language list                # 列出支持的语言
notebooklm language set zh_Hans         # 设置为简体中文
notebooklm language get                 # 查看当前语言
```

### 诊断
```bash
notebooklm auth check --test            # 认证诊断
notebooklm doctor                       # 健康检查
notebooklm metadata --json              # 导出元数据
```

## Autonomy Rules（Hermes 自动执行规则）

### 自动执行（无需确认）
- `notebooklm status`
- `notebooklm auth check`
- `notebooklm list`
- `notebooklm source list`
- `notebooklm language list/get/set`
- `notebooklm ask "..."`（不带 --save-as-note）
- `notebooklm create`
- `notebooklm source add`
- `notebooklm use <id>`
- `notebooklm profile list/create/switch`
- `notebooklm doctor`

### 需要确认
- `notebooklm delete`
- `notebooklm generate *`（长时间运行）
- `notebooklm download *`（写入文件系统）
- `notebooklm ask "..." --save-as-note`

## Hermes 提示词

当用户要求：
- "创建笔记本" → `notebooklm create`
- "添加来源/URL" → `notebooklm source add`
- "生成播客/音频" → `notebooklm generate audio`
- "生成视频" → `notebooklm generate video`
- "生成测验" → `notebooklm generate quiz`
- "下载" → `notebooklm download`
- "问/总结/分析" → `notebooklm ask`

执行前先检查认证状态，未认证则调用 google-auth skill。
