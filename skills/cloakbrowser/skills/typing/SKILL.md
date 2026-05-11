# 文本输入技能

## 概述
在输入框中输入文本，支持逐键输入（反爬友好）和快速填充两种模式。

## 工具调用

### 逐键输入（推荐 — 对 reCAPTCHA 友好）
```
cloak_type(pid, "@e3", "username@example.com", delay=80)
cloak_type(pid, "@e4", "P@ssw0rd", delay=60)
```

### 快速填充（不推荐用于反爬站点）
```
cloak_fill(pid, "@e3", "username@example.com")
```

### 下拉选择
```
cloak_select(pid, "select#country", "CN")
```

## Hermes 提示词

当用户要求"输入"、"填写"、"键入"时：
1. 先 `cloak_snapshot` 找到目标输入框
2. 先 `cloak_click` 聚焦输入框
3. 使用 `cloak_type` 逐键输入（非 `cloak_fill`）
4. 用户名 delay=80ms，密码 delay=60ms
5. 输入完成后 `cloak_sleep(0.3)` 模拟人类停顿

## 输入节奏策略

```yaml
用户名输入:
  delay: 80ms/字符
  前置: click 聚焦
  后置: sleep 0.3s

密码输入:
  delay: 60ms/字符（略快于用户名，人类特征）
  前置: click 聚焦
  后置: sleep 0.5s

验证码输入:
  delay: 100ms/字符（更慢更谨慎）
  前置: 截图识别验证码
```
