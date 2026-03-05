resource "kubernetes_namespace" "moodle" {
  metadata {
    name = "moodle"

    annotations = {
      name = "moodle"
    }
  }

  depends_on = [alicloud_cs_kubernetes_node_pool.pool]
}

resource "kubernetes_secret" "pgbouncer_config" {
  metadata {
    name      = "pgbouncer-config"
    namespace = kubernetes_namespace.moodle.metadata[0].name
  }

  data = {
    DB_HOST                   = local.rds_rw_connection_string
    DB_PORT                   = tostring(local.rds_rw_port)
    DB_NAME                   = alicloud_db_database.moodle.data_base_name
    DB_USER                   = alicloud_rds_account.moodle.account_name
    DB_PASSWORD               = random_password.moodle_db_password.result
    MAX_CLIENT_CONN           = var.pgbouncer_max_client_conn
    DEFAULT_POOL_SIZE         = var.pgbouncer_default_pool_size
    POOL_MODE                 = "session"
    IGNORE_STARTUP_PARAMETERS = "options"
    SERVER_TLS_SSLMODE        = var.pgbouncer_server_tls_sslmode
    MIN_POOL_SIZE             = var.pgbouncer_min_pool_size
  }

  type = "Opaque"
}

resource "kubernetes_secret" "pgbouncer_config_read_replica" {
  metadata {
    name      = "pgbouncer-config-read-replica"
    namespace = kubernetes_namespace.moodle.metadata[0].name
  }

  data = {
    DB_HOST                   = local.rds_ro_connection_string
    DB_PORT                   = tostring(local.rds_ro_port)
    DB_NAME                   = alicloud_db_database.moodle.data_base_name
    DB_USER                   = alicloud_rds_account.moodle.account_name
    DB_PASSWORD               = random_password.moodle_db_password.result
    MAX_CLIENT_CONN           = var.pgbouncer_max_client_conn
    DEFAULT_POOL_SIZE         = var.pgbouncer_default_pool_size
    POOL_MODE                 = "transaction"
    IGNORE_STARTUP_PARAMETERS = "options"
    SERVER_TLS_SSLMODE        = var.pgbouncer_server_tls_sslmode
    MIN_POOL_SIZE             = var.pgbouncer_min_pool_size
  }

  type = "Opaque"
}

resource "kubernetes_secret" "moodle_config" {
  metadata {
    name      = "moodle-config"
    namespace = kubernetes_namespace.moodle.metadata[0].name
  }

  data = {
    OBJECTFS_S3_ENABLED     = var.objectfs_s3_enabled ? "1" : "0"
    OBJECTFS_S3_KEY         = var.objectfs_s3_enabled && !var.objectfs_s3_use_sdk_creds ? coalesce(var.objectfs_s3_access_key, try(alicloud_ram_access_key.objectfs_s3[0].id, null), "") : ""
    OBJECTFS_S3_SECRET      = var.objectfs_s3_enabled && !var.objectfs_s3_use_sdk_creds ? coalesce(var.objectfs_s3_secret, try(alicloud_ram_access_key.objectfs_s3[0].secret, null), "") : ""
    OBJECTFS_S3_BUCKET      = var.objectfs_s3_enabled ? local.objectfs_s3_bucket_name_effective : ""
    OBJECTFS_S3_REGION      = var.objectfs_s3_enabled ? local.objectfs_s3_region_effective : ""
    OBJECTFS_S3_BASE_URL    = var.objectfs_s3_enabled ? local.objectfs_s3_base_url_effective : ""
    OBJECTFS_S3_KEY_PREFIX  = var.objectfs_s3_enabled ? local.objectfs_s3_key_prefix_normalized : ""
    OBJECTFS_S3_USESDKCREDS = var.objectfs_s3_use_sdk_creds ? "1" : "0"

    REDIS_SESSION_HOST     = var.redis_session_host
    REDIS_SESSION_PORT     = var.redis_session_port
    REDIS_CACHE_HOST       = var.redis_cache_host
    REDIS_CACHE_PORT       = var.redis_cache_port
    MUC_AUTOCONFIG_ENABLED = var.moodle_muc_autoconfig_enabled ? "1" : "0"

    DATABASE_HOST      = "pgbouncer-svc"
    DATABASE_HOST_READ = "pgbouncer-read-svc"
    DATABASE_PORT      = tostring(local.rds_rw_port)
    DATABASE_NAME      = alicloud_db_database.moodle.data_base_name
    DATABASE_USER      = alicloud_rds_account.moodle.account_name
    DATABASE_PASSWORD  = random_password.moodle_db_password.result
    DATABASE_PREFIX    = var.moodle_database_prefix

    WWW_ROOT  = var.moodle_www_root
    DATA_ROOT = var.moodle_data_root
    ADMIN     = var.moodle_admin_user
    SSL_PROXY = var.moodle_ssl_proxy

    OSS_ASSETS_BUCKET = alicloud_oss_bucket.moodle_assets.bucket
    OSS_CONFIG_BUCKET = alicloud_oss_bucket.moodle_config.bucket
  }

  type = "Opaque"

  lifecycle {
    precondition {
      condition = (
        !var.objectfs_s3_enabled
        || var.objectfs_s3_use_sdk_creds
        || local.objectfs_s3_static_credentials
        || local.objectfs_s3_manage_ram_credentials
      )
      error_message = "ObjectFS with objectfs_s3_use_sdk_creds=false requires static objectfs_s3_access_key/objectfs_s3_secret, or set objectfs_s3_create_ram_credentials=true."
    }
  }
}
