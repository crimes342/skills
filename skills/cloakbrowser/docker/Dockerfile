FROM --platform=linux/arm64 python:3.12-slim

LABEL maintainer="hermes-cloak"
LABEL description="Hermes Agent + CloakBrowser 反爬自动化 (ARM64)"

# 系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    libnspr4 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libcups2t64 libdrm2 libdbus-1-3 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2t64 \
    fonts-noto-color-emoji fonts-freefont-ttf fonts-unifont \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 预下载 CloakBrowser ARM64 二进制
RUN python -m cloakbrowser install 2>/dev/null || true

# 复制项目文件
COPY scripts/start.sh /app/start.sh
RUN chmod +x /app/start.sh

# 数据卷
VOLUME ["/data/cloak_profiles"]

# 启动
CMD ["/app/start.sh"]
