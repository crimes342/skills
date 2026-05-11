# 🔐 登录技能（核心）

## 概述
复合登录技能，整合浏览器启动、导航、表单填写、提交、验证的完整流程。

## 完整工具调用序列

```
Step 1:  cloak_launch(headless=true, humanize=true, profile_dir="/data/cloak_profiles/{domain}")
Step 2:  cloak_navigate(pid, "https://{target}/login")
Step 3:  cloak_snapshot(pid)                          → 识别 [@e1]=用户名, [@e2]=密码, [@e3]=登录按钮
Step 4:  cloak_click(pid, "@e1")                       → 聚焦用户名框
Step 5:  cloak_type(pid, "@e1", "{username}", delay=80) → 逐键输入用户名
Step 6:  cloak_sleep(0.3)                              → 人类停顿
Step 7:  cloak_click(pid, "@e2")                       → 聚焦密码框
Step 8:  cloak_type(pid, "@e2", "{password}", delay=60) → 逐键输入密码
Step 9:  cloak_sleep(0.5)                              → 人类停顿
Step 10: cloak_click(pid, "@e3")                       → 点击登录按钮
Step 11: cloak_wait_for_navigation(timeout=30000)      → 等待跳转
Step 12: cloak_snapshot(pid)                           → 验证登录结果
Step 13: cloak_get_cookies(pid)                        → 保存会话
Step 14: cloak_screenshot(pid)                         → 存档截图
```

## Hermes 提示词模板

```markdown
你是一个浏览器自动化专家，负责执行登录操作。

当用户要求登录某个网站时，严格按照以下流程执行：

### 第一阶段：准备
1. 确认浏览器已启动（如未启动则 cloak_launch）
2. 确认使用正确的 profile_dir（按目标站点命名）
3. 如果目标站点有强反爬，切换到 headed + Xvfb 模式

### 第二阶段：导航与识别
4. cloak_navigate 到登录页面
5. cloak_snapshot 获取页面元素列表
6. 识别用户名输入框、密码输入框、登录按钮的 [@eN] ref
7. 如果无法识别，截图并询问用户

### 第三阶段：填写凭据
8. cloak_click 用户名框 → cloak_type 用户名 (delay=80)
9. cloak_sleep(0.3)
10. cloak_click 密码框 → cloak_type 密码 (delay=60)
11. cloak_sleep(0.5)

### 第四阶段：提交与验证
12. cloak_click 登录按钮
13. cloak_wait_for_navigation(timeout=30000)
14. cloak_snapshot 验证登录是否成功
15. 检查标志：URL 变化、welcome 文本、dashboard 元素、logout 按钮

### 第五阶段：保存
16. cloak_get_cookies 保存会话
17. cloak_screenshot 存档

### 异常处理
- 出现 CAPTCHA → 截图通知用户手动处理
- 登录失败 → 截图 + 分析错误信息 + 报告
- 页面超时 → 重试（最多 3 次）
- 被反爬拦截 → 建议切换 headed+Xvfb 或更换代理

### 输出格式
向用户报告：
- ✅/❌ 登录状态
- 当前 URL 和页面标题
- Cookie 数量
- 截图路径
```

## 登录流程图

```
用户: "登录 example.com, 用户名 admin, 密码 123456"
                    │
                    ▼
            ┌───────────────┐
            │ cloak_launch  │ ← headless + humanize
            └───────┬───────┘
                    ▼
            ┌───────────────────┐
            │ cloak_navigate    │ → https://example.com/login
            └───────┬───────────┘
                    ▼
            ┌───────────────────┐
            │ cloak_snapshot    │ → [@e1]=用户名 [@e2]=密码 [@e3]=按钮
            └───────┬───────────┘
                    ▼
        ┌───────────┴───────────┐
        ▼                       ▼
  ┌──────────┐           ┌──────────┐
  │cloak_type│           │cloak_type│
  │ @e1 admin│           │ @e2 123  │
  │ delay=80 │           │ delay=60 │
  └────┬─────┘           └────┬─────┘
       │    cloak_sleep(0.3)  │
       └──────────┬───────────┘
                  ▼
          ┌───────────────┐
          │ cloak_click   │ → @e3 登录按钮
          └───────┬───────┘
                  ▼
          ┌───────────────────────┐
          │ cloak_wait_for_nav    │ → 等待跳转
          └───────┬───────────────┘
                  ▼
          ┌───────────────────┐
          │ cloak_snapshot    │ → 检查: Welcome? Dashboard? Error?
          └───────┬───────────┘
                  ▼
       ┌──────────┴──────────┐
       ▼                     ▼
  ┌─────────┐          ┌──────────┐
  │ 成功 ✅  │          │ 失败 ❌   │
  │ cookies │          │ 截图     │
  │ 截图    │          │ 分析原因  │
  └─────────┘          └──────────┘
```

## 强反爬站点升级策略

```yaml
标准模式（一般站点）:
  headless: true
  humanize: true
  延迟: 标准

升级模式（Cloudflare/DataDome/reCAPTCHA v3）:
  headless: false
  xvfb: true（Xvfb :99 -screen 0 1920x1080x24）
  humanize: true
  proxy: 住宅代理
  geoip: true（时区匹配代理 IP）
  延迟: 增加 50%
  预热: 先浏览 2-3 个其他页面再登录
```
