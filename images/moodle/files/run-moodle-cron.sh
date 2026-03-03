#!/bin/bash
set -euo pipefail

if php /var/www/html/admin/cli/cfg.php --name=release --no-eol >/dev/null 2>&1; then
  php /var/www/html/admin/cli/cron.php >/dev/null 2>&1 || true
else
  echo "Moodle DB not initialized yet, skip cron tick."
fi
