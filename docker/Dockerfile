# ayang ThinkPHP6 开箱镜像：Nginx + PHP-FPM（MySQL 使用宿主机 aaPanel）
FROM php:7.4-fpm-bullseye

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    APP_DIR=/var/www/ayang

# PHP 7.4 / bullseye 已 EOL：仅使用 archive 主仓库
RUN printf 'deb http://archive.debian.org/debian bullseye main\n' > /etc/apt/sources.list \
    && printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99no-check-valid \
    && apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        supervisor \
        cron \
        curl \
        unzip \
        default-mysql-client \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libzip-dev \
        libonig-dev \
        libxml2-dev \
        $PHPIZE_DEPS \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        bcmath \
        gd \
        mbstring \
        mysqli \
        pdo_mysql \
        zip \
        opcache \
        pcntl \
        sockets \
    && pecl install redis-5.3.7 \
    && docker-php-ext-enable redis opcache \
    && rm -rf /var/lib/apt/lists/* /tmp/pear \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# PHP 运行参数（对齐源站关键项）
RUN { \
      echo 'memory_limit=128M'; \
      echo 'upload_max_filesize=50M'; \
      echo 'post_max_size=50M'; \
      echo 'max_execution_time=300'; \
      echo 'date.timezone=PRC'; \
      echo 'opcache.enable=1'; \
      echo 'opcache.memory_consumption=128'; \
      echo 'opcache.validate_timestamps=1'; \
    } > /usr/local/etc/php/conf.d/ayang.ini

COPY docker/nginx.conf /etc/nginx/sites-available/default
COPY docker/supervisord.conf /etc/supervisor/conf.d/ayang.conf
COPY docker/crontab /etc/cron.d/ayang
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 0644 /etc/cron.d/ayang \
    && sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh \
    && rm -f /etc/nginx/sites-enabled/default \
    && ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default \
    && mkdir -p /var/log/supervisor /run/nginx \
    && sed -i 's|^listen = .*|listen = 127.0.0.1:9000|' /usr/local/etc/php-fpm.d/www.conf

# 应用代码（.dockerignore 已排除大包/密钥）
WORKDIR ${APP_DIR}
COPY --chown=www-data:www-data . ${APP_DIR}

RUN mkdir -p runtime/cache runtime/log runtime/session runtime/backup public/uploads public/tmp \
    && rm -f public/.user.ini \
    && chmod +x docker/scripts/*.sh \
    && sed -i 's/\r$//' docker/scripts/*.sh \
    && chown -R www-data:www-data runtime public/uploads public/tmp \
    && chmod -R 775 runtime public/uploads public/tmp \
    && rm -f .env || true

EXPOSE 8088

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8088/ || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
