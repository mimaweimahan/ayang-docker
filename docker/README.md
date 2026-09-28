# ayang Docker 开箱部署

应用（Nginx + PHP-FPM 7.4 + ThinkPHP6 + 定时任务）打包进镜像；**MySQL 使用宿主机 aaPanel 创建的库**，不进容器。

## 架构

```
浏览器 → aaPanel 反代(可选) → 容器 Nginx:8088 → PHP-FPM → 宿主机 aaPanel MySQL:3306
```

`network_mode: host`，容器内 `127.0.0.1:3306` 即 aaPanel 的 MySQL；HTTP 默认 **8088**，不与面板抢 80。

## 一、aaPanel 准备（目标机）

1. **Database** → 添加库：
   - 库名：`xinayang`
   - 用户：`xinayang`
   - 权限：本地
2. 导入数据（任选）：
   - 源站 `database/backup/` 分卷还原，或
   - 源站现导一份 `mysqldump` 后在面板导入
3. （推荐）新建站点域名，反向代理到 `http://127.0.0.1:8088`。

## 二、构建与启动

```bash
cd /path/to/ayang.sgesge.com

# 1. 配置密码
cp docker/.env.docker.example docker/.env.docker
# 编辑 DB_PASS=...

# 2. 构建镜像（含程序代码）
docker compose -f docker/docker-compose.yml --env-file docker/.env.docker build

# 3. 启动
docker compose -f docker/docker-compose.yml --env-file docker/.env.docker up -d

# 4. 查看
docker ps | grep ayang
docker logs -f ayang-app
curl -I http://127.0.0.1:8088/
```

## 三、镜像备份位置与新机一条命令部署

**当前默认**：镜像只在跑应用的那台机本地 Docker 里（`ayang-app:latest`），**不会自动备份到别处**。

导出到磁盘（建议定期做）：

```bash
# 默认写到 /www/backup/ayang/ayang-app-latest.tar.gz（保留最近 2 个带时间戳包）
bash docker/export-image.sh
# 或指定目录：bash docker/export-image.sh /path/to/dir
```

新 VPS **一条命令**（需已装 Docker；aaPanel 已建好 `xinayang` 库并导入数据）：

```bash
# 先把 ayang-app-latest.tar.gz 和 docker/oneclick-deploy.sh 拷到新机，然后：
DB_PASS='你的库密码' bash oneclick-deploy.sh /path/to/ayang-app-latest.tar.gz
```

脚本会：`docker load` → 写 compose/env → `up -d` → 探测 `http://127.0.0.1:8088/`。  
数据库、七牛密钥、SSL **不在镜像包里**，需在新机面板单独准备。

## 四、说明

| 项 | 说明 |
|----|------|
| PHP | 7.4 + bcmath / pdo_mysql / gd / opcache / redis |
| 定时任务 | 见下表（已打进镜像 cron） |
| 密钥 | `.env` 不进镜像，启动时按环境变量生成 |
| 持久化 | `uploads`、`runtime`、`runtime/backup` 使用 named volume |
| 不包含 | MySQL 进程、SSL 证书、七牛云上传（备份在本地 volume） |

### 镜像内定时任务（对齐源站宝塔）

| 时间 | 对应源站 | 动作 |
|------|----------|------|
| 每天 12:01 | qq qq | `cron_reset_orders.php` |
| 每天 12:30 | 备份MySQL | `mysqldump` → `runtime/backup/`，保留 2 份 |
| 每天 01:30 | ql | 清理应用/Nginx/过期 session、cache 日志 |

> 说明：源站 ql 清的是宿主机 `/var/log/*`；容器内改为清应用自身日志。若仍需清宿主机系统日志，在 aaPanel 计划任务再建一条即可。

### 七牛云备份（目标机 aaPanel，不进镜像）

| 项 | 说明 |
|----|------|
| 时间 | 每天 **12:35**（错开容器本地 12:30） |
| 任务名 | 备份MySQL[xinayang]→七牛 |
| 脚本 | `/www/server/cron/ayang_qiniu_backup.py` |
| 远端路径 | `wmt-1/ayang/shujuku/database/mysql/xinayang/` |
| 保留 | 云端最新 **2** 份 |

密钥在面板七牛插件配置中，不进 Docker 镜像。

## 五、常见问题

**MySQL 连不上**：检查面板库用户是否仅允许 `localhost`；`network_mode: host` 下应使用 `127.0.0.1`。

**改端口**：编辑 `docker/nginx.conf` 的 `listen`，重建镜像即可。

**更新代码**：改代码后重新 `build` + `up -d`；uploads/runtime 在 volume 中会保留。
