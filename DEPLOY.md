# ayang 新 VPS 部署流程

应用镜像推到 **GitHub Container Registry (ghcr.io)**，代码与编排进 **私有 GitHub 仓库**。  
数据库密码、七牛密钥 **永不入库**。

---

## 架构选择

| 模式 | 适用 | 命令要点 |
|------|------|----------|
| A. 全自动 | 全新 VPS，不想装 aaPanel 库 | `--with-mysql`（容器自带 MySQL） |
| B. 现网同款 | 已有 aaPanel MySQL | 先建库导入，再跑 bootstrap（不加 `--with-mysql`） |

默认 HTTP：**8088**。

---

## 一、维护机：首次发布到 GitHub（只需做一次）

### 1. 准备 Token

GitHub → Settings → Developer settings → Personal access tokens  
权限至少：`repo`、`write:packages`、`read:packages`、`delete:packages`（可选）。

```bash
export GH_TOKEN='github_pat_xxx'
export GITHUB_OWNER='你的GitHub用户名'
export GITHUB_REPO='ayang-deploy'
export GITHUB_USER="$GITHUB_OWNER"
```

### 2. 创建私有仓库并推送代码

在已整理好的部署目录（本仓库）执行：

```bash
cd /path/to/ayang-deploy
git init -b main
git add -A
git status   # 确认无 .env / 密码 / tar.gz
git commit -m "chore: ayang docker deploy kit"
gh auth login --with-token <<< "$GH_TOKEN"
gh repo create "$GITHUB_OWNER/$GITHUB_REPO" --private --source=. --remote=origin --push
```

### 3. 推送 Docker 镜像到 GHCR

在已有 `ayang-app:latest` 的机器（如当前生产 VPS）：

```bash
export GH_TOKEN=...
export GITHUB_OWNER=...
# 可选：同时上传 tar 到 Release 作为 pull 失败时的兜底
UPLOAD_RELEASE=1 bash scripts/publish-image.sh
```

推送后镜像地址：

`ghcr.io/<OWNER>/ayang-app:latest`

在 GitHub 仓库 → Packages 将该 package 设为 **Private**，并确认 Token 可读。

### 4.（可选）准备 SQL 初始化包

```bash
# 在数据库机导出
mysqldump -uxinayang -p xinayang | gzip > xinayang.sql.gz
# 放到新机任意路径，部署时 --sql-file 指向它
# 不要提交到 Git
```

---

## 二、新 VPS：一条命令部署

### 模式 A — 全自动（推荐新机）

```bash
export GH_TOKEN='github_pat_xxx'
export GITHUB_OWNER='你的用户名'
export DB_PASS='请设一个强密码'
export MYSQL_ROOT_PASSWORD='再设一个强密码'   # 可省略，将与 DB_PASS 相同

# 把 xinayang.sql.gz 先 scp 到新机，例如 /root/xinayang.sql.gz
curl -fsSL -H "Authorization: token $GH_TOKEN"   "https://raw.githubusercontent.com/$GITHUB_OWNER/ayang-deploy/main/scripts/bootstrap.sh"   -o /tmp/bootstrap.sh
chmod +x /tmp/bootstrap.sh

bash /tmp/bootstrap.sh   --owner "$GITHUB_OWNER"   --with-mysql   --sql-file /root/xinayang.sql.gz
```

完成后访问：`http://新VPS的IP:8088/`

### 模式 B — aaPanel MySQL（对齐现网）

1. 安装 aaPanel，创建库 `xinayang` / 用户 `xinayang`，导入 SQL  
2. 执行：

```bash
export GH_TOKEN=...
export GITHUB_OWNER=...
export DB_PASS='面板里该库的密码'

bash /tmp/bootstrap.sh --owner "$GITHUB_OWNER"
# 不加 --with-mysql，容器用 host 网络连 127.0.0.1:3306
```

3. （可选）面板反代到 `http://127.0.0.1:8088`  
4. （可选）按现网装七牛插件并配置云备份计划任务

---

## 三、日常更新

```bash
# 1) 有代码变更：在构建机 docker compose build 出新 ayang-app:latest
# 2) 推镜像
UPLOAD_RELEASE=0 bash scripts/publish-image.sh

# 3) 新机或现机拉新镜像重启
cd /www/wwwroot/ayang-docker
docker pull ghcr.io/$GITHUB_OWNER/ayang-app:latest
docker compose -f docker/docker-compose.yml --env-file docker/.env.docker up -d
# 或 portable 模式用 docker-compose.portable.yml
```

---

## 四、备份说明

| 内容 | 位置 |
|------|------|
| 应用镜像 | `ghcr.io/<OWNER>/ayang-app:latest`（+ 可选 Release tar） |
| 代码/编排 | GitHub 私有仓 `ayang-deploy` |
| 数据库 | 现网：七牛 + 容器本地 volume；全自动模式：MySQL volume `ayang_mysql_data` |
| 上传文件 | Docker volume `ayang_uploads` |

重启容器 **不会丢库**（库在 volume 或宿主机 MySQL）。

---

## 五、防火墙

放行 **8088**（及若用容器 MySQL 且需外部连库时的 3306，一般不放行）。
