# 截图与快照技能

## 概述
获取页面截图和无障碍树快照，用于验证操作结果和调试。

## 工具调用

### 页面快照（推荐 — 返回结构化元素列表）
```
cloak_snapshot(pid)
# 返回: [@e1]=输入框 "Username", [@e2]=输入框 "Password", [@e3]=按钮 "Login"
```

### 截图
```
cloak_screenshot(pid)                    # 视口截图
cloak_screenshot(pid, full_page=true)    # 全页截图
cloak_screenshot(pid, selector="#form")  # 元素截图
```

### 读取页面内容
```
cloak_read_page(pid)    # 返回页面可见文本
```

## Hermes 提示词

当用户要求"截图"、"看看页面"、"确认状态"时：
1. 调用 `cloak_snapshot` 获取结构化元素信息
2. 如果需要视觉确认，调用 `cloak_screenshot`
3. 如果需要文本内容，调用 `cloak_read_page`
4. 分析结果并向用户报告

## 使用场景

| 场景 | 工具 | 返回 |
|------|------|------|
| 识别登录表单 | cloak_snapshot | 元素 ref 列表 |
| 验证登录成功 | cloak_snapshot | 检查 welcome/logout 元素 |
| 调试失败原因 | cloak_screenshot | 页面截图 |
| 提取页面数据 | cloak_read_page | 可见文本 |
| 记录操作证据 | cloak_screenshot | 存档截图 |
