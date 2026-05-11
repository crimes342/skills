# 页面导航技能

## 概述
控制浏览器在页面间导航，包括 URL 跳转、前进后退、刷新。

## 工具调用

### 导航到 URL
```
cloak_navigate(pid, "https://target.com/page")
```

### 页面管理
```
cloak_new_page()              # 新建标签页
cloak_list_pages()            # 列出所有页面
cloak_switch_page(page_id)    # 切换标签页
```

### 浏览历史
```
cloak_back()     # 后退
cloak_forward()  # 前进
cloak_reload()   # 刷新
```

## Hermes 提示词

当用户要求"打开某个网站"、"跳转到"、"访问"时：
1. 如果浏览器未启动，先调用 `cloak_launch`
2. 调用 `cloak_navigate` 跳转到目标 URL
3. 调用 `cloak_snapshot` 确认页面加载完成
4. 向用户报告页面标题和关键内容

## 等待策略

```
cloak_wait_for_selector("#content", timeout=10000)  # 等待元素出现
cloak_wait_for_navigation(timeout=30000)             # 等待导航完成
cloak_sleep(2)                                        # 固定等待
```

优先使用 `wait_for_selector` 而非固定 sleep，更可靠且对 reCAPTCHA 更友好。
