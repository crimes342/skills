# 页面交互技能

## 概述
与页面元素交互：点击、悬停、键盘操作、滚动。

## 工具调用

### 点击
```
cloak_click(pid, "@e5")     # 通过 snapshot ref 点击（推荐）
cloak_click(pid, "#button") # 通过 CSS 选择器点击
```

### 悬停
```
cloak_hover(pid, "@e3")     # 鼠标悬停
```

### 键盘
```
cloak_press_key("Enter")    # 按回车
cloak_press_key("Tab")      # 按 Tab 切换焦点
cloak_press_key("Escape")   # 按 Esc
```

### 滚动
```
cloak_scroll("down", 500)   # 向下滚动 500px
cloak_scroll("up", 300)     # 向上滚动
```

## Hermes 提示词

当用户要求"点击"、"按"、"滚动"、"悬停"时：
1. 先调用 `cloak_snapshot` 获取页面元素列表
2. 根据用户描述匹配对应的 `[@eN]` ref
3. 调用对应的交互工具
4. 交互后调用 `cloak_snapshot` 确认结果

## 反检测注意

- 点击前先 `cloak_snapshot` 确认元素位置
- humanize=True 时，鼠标移动使用贝塞尔曲线
- 避免过快连续操作，适当插入 `cloak_sleep(0.5-1.5)`
