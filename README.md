# ayang-docker

ThinkPHP6 后台 Docker 一键部署包。

**完整说明 → [DEPLOY.md](./DEPLOY.md)**

```bash
export GH_TOKEN=... DB_PASS=...
bash <(curl -fsSL -H "Authorization: token $GH_TOKEN" \
  https://raw.githubusercontent.com/mimaweimahan/ayang-docker/main/scripts/bootstrap.sh) --with-mysql
```

切勿提交 `.env`、真实密码、七牛密钥。
