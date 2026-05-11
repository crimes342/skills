FROM --platform=linux/arm64 python:3.12-slim

LABEL maintainer="hermes-notebooklm"
LABEL description="Hermes + CloakBrowser + NotebookLM 适配 (ARM64)"

# 系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    libnspr4 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libcups2t64 libdrm2 libdbus-1-3 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2t64 \
    fonts-noto-color-emoji fonts-freefont-ttf fonts-unifont \
    cron \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 预下载
RUN python -m cloakbrowser install 2>/dev/null || true
RUN playwright install chromium 2>/dev/null || true

# 复制文件
COPY scripts/cloak2nlm_bridge.py /app/
COPY docker/start.sh /app/
RUN chmod +x /app/start.sh

# Cron: 每15分钟刷新 Cookie
RUN echo "*/15 * * * * root python3 /app/cloak2nlm_bridge.py >> /var/log/nlm-bridge.log 2>&1" > /etc/cron.d/nlm-refresh

VOLUME ["/data/cloak_profiles", "/root/.notebooklm"]

CMD ["/app/start.sh"]
