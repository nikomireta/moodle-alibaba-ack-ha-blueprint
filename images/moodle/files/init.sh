#!/bin/bash
set -euo pipefail

template_vars='${DATABASE_HOST} ${DATABASE_NAME} ${DATABASE_USER} ${DATABASE_PASSWORD} ${DATABASE_PREFIX} ${DATABASE_PORT} ${DATABASE_HOST_READ} ${WWW_ROOT} ${DATA_ROOT} ${ADMIN} ${OBJECTFS_S3_ENABLED} ${SSL_PROXY} ${REDIS_SESSION_HOST} ${REDIS_SESSION_PORT}'
envsubst "${template_vars}" < /var/www/html/config.php.template > /var/www/html/config.php
chown www-data:www-data /var/www/html/config.php

mkdir -p /var/www/localdata/cache /var/www/localdata/request
chown -R www-data:www-data /var/www/localdata

normalise_bool() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y|on) echo "1" ;;
    *) echo "0" ;;
  esac
}

is_moodle_db_ready() {
  php /var/www/html/admin/cli/cfg.php --name=release --no-eol >/tmp/moodle-db-ready.log 2>&1
}

rebuild_component_cache() {
  php /var/www/html/admin/cli/alternative_component_cache.php --rebuild >/tmp/alternative-component-cache.log 2>&1 || true
}

configure_muc_cache() {
  local muc_autoconfig_enabled

  muc_autoconfig_enabled="$(normalise_bool "${MUC_AUTOCONFIG_ENABLED:-1}")"
  if [ "${muc_autoconfig_enabled}" != "1" ]; then
    echo "MUC auto-config disabled; keep existing cache mapping."
    return 0
  fi

  if [ ! -f /var/www/html/configure_muc.php ]; then
    echo "MUC auto-config script not found; skip."
    return 0
  fi

  php /var/www/html/configure_muc.php >/tmp/muc-autoconfig.log 2>&1 || {
    echo "MUC auto-config failed; keep existing cache mapping."
    return 0
  }

  php /var/www/html/admin/cli/purge_caches.php >/tmp/purge-caches.log 2>&1 || true
  echo "MUC cache configuration applied."
}

run_objectfs_cfg() {
  local key="$1"
  local value="$2"
  php /var/www/html/admin/cli/cfg.php --component=tool_objectfs --name="${key}" --set="${value}" >/tmp/objectfs-cfg.log 2>&1
}

configure_objectfs_s3() {
  local usesdkcreds
  local objectfs_enabled

  objectfs_enabled="$(normalise_bool "${OBJECTFS_S3_ENABLED:-0}")"
  if [ "${objectfs_enabled}" != "1" ]; then
    echo "ObjectFS disabled; skip automatic cfg bootstrap."
    return 0
  fi

  usesdkcreds="$(normalise_bool "${OBJECTFS_S3_USESDKCREDS:-0}")"

  if [ -z "${OBJECTFS_S3_BUCKET:-}" ] || [ -z "${OBJECTFS_S3_REGION:-}" ] || [ -z "${OBJECTFS_S3_BASE_URL:-}" ]; then
    echo "ObjectFS S3 env incomplete; skip automatic cfg bootstrap."
    return 0
  fi

  if [ "${usesdkcreds}" = "0" ] && { [ -z "${OBJECTFS_S3_KEY:-}" ] || [ -z "${OBJECTFS_S3_SECRET:-}" ]; }; then
    echo "ObjectFS S3 key/secret missing and sdk creds disabled; skip automatic cfg bootstrap."
    return 0
  fi

  run_objectfs_cfg "filesystem" '\tool_objectfs\s3_file_system' || return 0
  run_objectfs_cfg "enabletasks" "1" || return 0
  run_objectfs_cfg "deletelocal" "1" || return 0
  run_objectfs_cfg "consistencydelay" "0" || return 0
  run_objectfs_cfg "sizethreshold" "0" || return 0
  run_objectfs_cfg "minimumage" "0" || return 0
  run_objectfs_cfg "s3_usesdkcreds" "${usesdkcreds}" || return 0
  run_objectfs_cfg "s3_bucket" "${OBJECTFS_S3_BUCKET}" || return 0
  run_objectfs_cfg "s3_region" "${OBJECTFS_S3_REGION}" || return 0
  run_objectfs_cfg "s3_base_url" "${OBJECTFS_S3_BASE_URL}" || return 0
  run_objectfs_cfg "key_prefix" "${OBJECTFS_S3_KEY_PREFIX:-}" || return 0

  if [ "${usesdkcreds}" = "0" ]; then
    run_objectfs_cfg "s3_key" "${OBJECTFS_S3_KEY}" || return 0
    run_objectfs_cfg "s3_secret" "${OBJECTFS_S3_SECRET}" || return 0
  fi

  echo "ObjectFS S3 configuration applied."
}

if is_moodle_db_ready; then
  rebuild_component_cache
  configure_muc_cache
  configure_objectfs_s3
else
  echo "Moodle DB not installed yet. Continue startup; run install_database.php manually."
fi

nginx -g 'daemon off;' &
php-fpm8.1 --nodaemonize &

wait -n
exit $?
