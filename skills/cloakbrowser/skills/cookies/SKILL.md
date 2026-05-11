# Cookie 管理技能

## 概述
读写浏览器 Cookie，实现会话持久化和跨请求复用。

## 工具调用

### 获取 Cookie
```
cloak_get_cookies(pid)
# 返回: [{"name": "session", "value": "abc123", "domain": ".example.com", ...}]
```

### 设置 Cookie
```
cloak_set_cookies(pid, [
  {"name": "session", "value": "abc123", "domain": ".example.com", "/"}
])
```

## Hermes 提示词

当用户要求"保存登录状态"、"获取 Cookie"、"复用会话"时：
1. 登录成功后调用 `cloak_get_cookies` 提取 Cookie
2. 将 Cookie 保存到文件或数据库
3. 下次访问时调用 `cloak_set_cookies` 恢复会话
4. 验证 Cookie 是否仍然有效（检查是否被重定向到登录页）

## 持久化策略

```yaml
方式 1 — Profile 持久化（推荐）:
  launch 时指定 profile_dir
  浏览器自动保存/恢复 Cookie、localStorage
  无需手动管理 Cookie

方式 2 — Cookie 文件:
  登录后 cloak_get_cookies → 保存到 JSON 文件
  下次启动后 cloak_set_cookies 恢复
  适合跨机器迁移

方式 3 — 两者结合:
  profile_dir 做主持久化
  Cookie 文件做备份/迁移
```
