# ayang 新 VPS 一键部署

仓库：[mimaweimahan/ayang-docker](https://github.com/mimaweimahan/ayang-docker)（请保持 **Private**）

Release `latest` 资产：
- `ayang-app-latest.tar.gz` — 应用镜像
- `xinayang.sql.gz` — 数据库初始化包

---

## 新机一条命令（全自动，推荐）

```bash
export GH_TOKEN='你的GitHub_PAT'   # 权限：repo（读私有仓/Release）
export DB_PASS='请设强密码'         # 同时作为 xinayang 用户密码
# 可选：export MYSQL_ROOT_PASSWORD='另一个强密码'

curl -fsSL -H "Authorization: token $GH_TOKEN" \
  https://raw.githubusercontent.com/mimaweimahan/ayang-docker/main/scripts/bootstrap.sh \
  -o /tmp/bootstrap.sh
chmod +x /tmp/bootstrap.sh

bash /tmp/bootstrap.sh --with-mysql
```

脚本会自动：装 Docker/Git → clone 仓库 → 下载镜像包与 SQL → 启动 MySQL+应用 → 探测 `:8088`。

完成后访问：`http://新VPS的IP:8088/`

---

## 模式 B：已有 aaPanel MySQL

1. 面板建库 `xinayang` / 用户 `xinayang`，导入 SQL（或用 Release 里的 `xinayang.sql.gz`）
2. 执行（**不要**加 `--with-mysql`）：

```bash
export GH_TOKEN=... DB_PASS='面板库密码'
bash /tmp/bootstrap.sh
```

---

## 维护：更新镜像 / SQL 到 Release

在有 `ayang-app:latest` 与数据库的机器上：

```bash
bash docker/export-image.sh /www/backup/ayang
# 导出 SQL
mysqldump -uxinayang -p'...' --single-transaction --quick --routines --triggers \
  --default-character-set=utf8mb4 --no-tablespaces xinayang | gzip > /www/backup/ayang/xinayang.sql.gz
# 上传到 Release latest（可用 scripts 或 GitHub 网页）
```

或：`UPLOAD_RELEASE=1 GH_TOKEN=... GITHUB_OWNER=mimaweimahan bash scripts/publish-image.sh`

---

## 一键范围 vs 需另配

| 已包含 | 需另配（可选） |
|--------|----------------|
| Docker 应用 + 定时任务（重置订单/本地备份/清日志） | 域名 / SSL / aaPanel 反代 |
| MySQL（`--with-mysql`）+ 数据初始化 | 七牛云备份（面板插件+密钥） |
| uploads/runtime 持久 volume | 防火墙放行 8088 |
| | 前端邀请域名 `FRONTEND_INVITE_BASE` |

重启容器不会丢库（MySQL volume 或宿主机库）。
