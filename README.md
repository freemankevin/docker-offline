# offline-install-docker

[![更新状态](https://github.com/freemankevin/offline-install-docker/actions/workflows/update.yml/badge.svg)](https://github.com/freemankevin/offline-install-docker/actions/workflows/update.yml)

🚀 自动化维护的 Docker 离线安装包，支持 x86_64 和 ARM64 架构。


## 📦 快速开始

### 下载离线包

前往 [Releases 页面](https://github.com/freemankevin/offline-install-docker/releases) 下载最新版本。

### 安装步骤

1. **解压下载的包**
   ```bash
   tar -xzf docker-offline-vX.X.X.tar.gz
   cd docker-offline-vX.X.X
   ```

2. **安装 Docker**
   ```bash
   bash ./packages/scripts/install.sh
   ```

3. **验证安装**
   ```bash
   docker --version
   docker-compose --version
   ```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！