# 浏览器生命周期技能

## 概述
管理 CloakBrowser 浏览器实例的启动、配置和关闭。

## 工具调用

### 启动浏览器
```
cloak_launch(
  headless=true,       # true=纯无头, false=有头(需Xvfb)
  humanize=true,       # 必须开启：贝塞尔鼠标轨迹+真实键盘时序
  proxy="",            # 可选：http://user:pass@host:port
  profile_dir="/data/cloak_profiles/{domain}",  # 持久化
  fingerprint_seed="{unique_seed}",              # 每站点唯一
  args=["--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"]
)
```

### 关闭浏览器
```
cloak_close()
```

## Hermes 提示词

当用户要求"打开浏览器"、"启动 CloakBrowser"、"开始自动化"时：
1. 调用 `cloak_launch` 启动实例
2. 如果目标网站有强反爬（Cloudflare/DataDome），使用 `headless=false` + Xvfb
3. 始终设置 `humanize=true`
4. 为每个目标站点使用独立的 `profile_dir` 实现会话隔离

## ARM64 无 GPU 配置

```bash
# 环境变量
CLOAK_HEADLESS=true
CLOAK_HUMANIZE=true

# 如果需要 headed 模式
Xvfb :99 -screen 0 1920x1080x24 &
export DISPLAY=:99
```
