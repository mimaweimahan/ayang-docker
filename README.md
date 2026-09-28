# ayang-deploy

ThinkPHP6 后台 Docker 部署包（Nginx + PHP-FPM 7.4 + 定时任务）。

- **完整流程** → [DEPLOY.md](./DEPLOY.md)
- **一键脚本** → [scripts/bootstrap.sh](./scripts/bootstrap.sh)
- **推镜像** → [scripts/publish-image.sh](./scripts/publish-image.sh)

## 新 VPS 最短命令（全自动）

```bash
export GH_TOKEN=... GITHUB_OWNER=... DB_PASS=...
bash bootstrap.sh --owner "$GITHUB_OWNER" --with-mysql --sql-file /root/xinayang.sql.gz
```

详见 DEPLOY.md。切勿把 `.env`、数据库密码、七牛密钥提交进仓库。
