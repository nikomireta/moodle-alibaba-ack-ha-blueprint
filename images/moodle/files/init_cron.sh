#!/bin/bash
set -euo pipefail

template_vars='${DATABASE_HOST} ${DATABASE_NAME} ${DATABASE_USER} ${DATABASE_PASSWORD} ${DATABASE_PREFIX} ${DATABASE_PORT} ${DATABASE_HOST_READ} ${WWW_ROOT} ${DATA_ROOT} ${ADMIN} ${OBJECTFS_S3_ENABLED} ${SSL_PROXY} ${REDIS_SESSION_HOST} ${REDIS_SESSION_PORT}'
envsubst "${template_vars}" < /var/www/html/config.php.template > /var/www/html/config.php
chown www-data:www-data /var/www/html/config.php

mkdir -p /var/www/localdata/cache /var/www/localdata/request
chown -R www-data:www-data /var/www/localdata

if ! grep -Fq '/usr/local/bin/run-moodle-cron.sh' /etc/crontab; then
  # Keep this job output-free in run-moodle-cron.sh so cron can run as www-data
  # without write permission to /proc/1/fd/*.
  echo '* * * * * www-data /usr/local/bin/run-moodle-cron.sh' >> /etc/crontab
fi

cron -f &
wait -n
exit $?
