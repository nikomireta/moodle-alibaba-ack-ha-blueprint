locals {
  rds_category_effective = var.rds_category

  rds_instance_charge_type_raw = var.rds_instance_charge_type

  rds_instance_charge_type_data = lower(local.rds_instance_charge_type_raw) == "postpaid" ? "PostPaid" : (
    lower(local.rds_instance_charge_type_raw) == "prepaid" ? "PrePaid" : local.rds_instance_charge_type_raw
  )

  rds_instance_charge_type_resource = lower(local.rds_instance_charge_type_raw) == "postpaid" ? "Postpaid" : (
    lower(local.rds_instance_charge_type_raw) == "prepaid" ? "Prepaid" : local.rds_instance_charge_type_raw
  )

  rds_db_instance_storage_type_effective = var.rds_db_instance_storage_type

  rds_instance_storage_gb_raw = coalesce(var.rds_instance_storage_gb, 512)

  rds_instance_storage_gb = max(5, ceil(local.rds_instance_storage_gb_raw / 5) * 5)

  rds_readonly_enabled = coalesce(var.rds_readonly_enabled, true)

  rds_readonly_instance_storage_gb_raw = coalesce(
    var.rds_readonly_instance_storage_gb,
    local.rds_instance_storage_gb
  )

  rds_readonly_instance_storage_gb = max(5, ceil(local.rds_readonly_instance_storage_gb_raw / 5) * 5)

  rds_is_ha_category      = contains(["highavailability", "alwayson", "finance", "cluster"], lower(local.rds_category_effective))
  rds_primary_vswitch_ids = local.rds_is_ha_category ? join(",", [alicloud_vswitch.db.id, alicloud_vswitch.db.id]) : alicloud_vswitch.db.id
  rds_zone_id_slave_a     = local.rds_is_ha_category ? alicloud_vswitch.db.zone_id : null

  rds_security_ips_effective = length(var.rds_security_ips) > 0 ? var.rds_security_ips : [alicloud_vpc.main.cidr_block]

  rds_is_china_region = startswith(var.region, "cn-")
  rds_readonly_commodity_code_effective = coalesce(
    var.rds_readonly_commodity_code,
    local.rds_instance_charge_type_data == "PrePaid" ? (
      local.rds_is_china_region ? "rds_rordspre_public_cn" : "rds_rordspre_public_intl"
      ) : (
      local.rds_is_china_region ? "rords" : "rords_intl"
    )
  )
}

data "alicloud_db_zones" "rds" {
  engine                   = "PostgreSQL"
  engine_version           = var.rds_pg_version
  instance_charge_type     = local.rds_instance_charge_type_data
  category                 = local.rds_category_effective
  db_instance_storage_type = local.rds_db_instance_storage_type_effective
  multi_zone               = false
}

data "alicloud_db_instance_classes" "primary" {
  zone_id                  = alicloud_vswitch.db.zone_id
  engine                   = "PostgreSQL"
  engine_version           = var.rds_pg_version
  category                 = local.rds_category_effective
  instance_charge_type     = local.rds_instance_charge_type_data
  db_instance_storage_type = local.rds_db_instance_storage_type_effective
}

data "alicloud_db_instance_classes" "readonly" {
  count = local.rds_readonly_enabled ? 1 : 0

  zone_id                  = alicloud_vswitch.db.zone_id
  engine                   = "PostgreSQL"
  engine_version           = var.rds_pg_version
  category                 = local.rds_category_effective
  instance_charge_type     = local.rds_instance_charge_type_data
  db_instance_storage_type = local.rds_db_instance_storage_type_effective
  commodity_code           = local.rds_readonly_commodity_code_effective
  db_instance_id           = alicloud_db_instance.main.id
}

locals {
  rds_primary_instance_type = coalesce(
    var.rds_instance_type,
    try(data.alicloud_db_instance_classes.primary.instance_classes[0].instance_class, null)
  )

  rds_readonly_instance_type = coalesce(
    var.rds_readonly_instance_type,
    try(data.alicloud_db_instance_classes.readonly[0].instance_classes[0].instance_class, null),
    local.rds_primary_instance_type
  )
}

resource "random_password" "moodle_db_password" {
  length      = 24
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

resource "alicloud_rds_service_linked_role" "pgsql_on_ecs" {
  count        = var.rds_create_service_linked_role ? 1 : 0
  service_name = "AliyunServiceRoleForRdsPgsqlOnEcs"
}

resource "alicloud_db_instance" "main" {
  engine                   = "PostgreSQL"
  engine_version           = var.rds_pg_version
  category                 = local.rds_category_effective
  instance_type            = local.rds_primary_instance_type
  instance_storage         = local.rds_instance_storage_gb
  instance_charge_type     = local.rds_instance_charge_type_resource
  instance_name            = substr("${local.name_prefix}-rds", 0, 63)
  zone_id                  = alicloud_vswitch.db.zone_id
  zone_id_slave_a          = local.rds_zone_id_slave_a
  vswitch_id               = local.rds_primary_vswitch_ids
  vpc_id                   = alicloud_vpc.main.id
  security_ips             = local.rds_security_ips_effective
  db_instance_storage_type = local.rds_db_instance_storage_type_effective
  security_group_ids       = [alicloud_security_group.rds.id]
  monitoring_period        = "60"
  tags                     = local.common_tags

  lifecycle {
    precondition {
      condition     = local.rds_primary_instance_type != null
      error_message = "RDS instance class could not be resolved. Set rds_instance_type explicitly for your zone."
    }
  }

  depends_on = [alicloud_rds_service_linked_role.pgsql_on_ecs]
}

resource "alicloud_db_readonly_instance" "read" {
  count                    = local.rds_readonly_enabled ? 1 : 0
  zone_id                  = alicloud_db_instance.main.zone_id
  master_db_instance_id    = alicloud_db_instance.main.id
  engine_version           = alicloud_db_instance.main.engine_version
  instance_storage         = local.rds_readonly_instance_storage_gb
  instance_type            = local.rds_readonly_instance_type
  instance_name            = substr("${local.name_prefix}-rds-ro", 0, 63)
  vswitch_id               = alicloud_vswitch.db.id
  instance_charge_type     = local.rds_instance_charge_type_resource
  db_instance_storage_type = local.rds_db_instance_storage_type_effective
  tags                     = local.common_tags

  lifecycle {
    precondition {
      condition     = local.rds_readonly_instance_type != null
      error_message = "RDS readonly instance class could not be resolved. Set rds_readonly_instance_type explicitly."
    }
    precondition {
      condition     = lower(local.rds_category_effective) != "basic"
      error_message = "RDS readonly instance is not supported for rds_category=Basic. Use HighAvailability/AlwaysOn (typically in a fresh stack or migration plan)."
    }
  }
}

resource "alicloud_db_database" "moodle" {
  instance_id    = alicloud_db_instance.main.id
  data_base_name = var.rds_database_name
}

resource "alicloud_rds_account" "moodle" {
  db_instance_id      = alicloud_db_instance.main.id
  account_name        = var.rds_account_name
  account_password    = random_password.moodle_db_password.result
  account_type        = "Normal"
  account_description = "Moodle application account"
}

resource "alicloud_db_account_privilege" "moodle" {
  instance_id  = alicloud_db_instance.main.id
  account_name = alicloud_rds_account.moodle.account_name
  privilege    = var.rds_account_privilege
  db_names     = [alicloud_db_database.moodle.data_base_name]
}

locals {
  rds_rw_connection_string = alicloud_db_instance.main.connection_string
  rds_rw_port              = alicloud_db_instance.main.port
  rds_ro_connection_string = local.rds_readonly_enabled ? alicloud_db_readonly_instance.read[0].connection_string : alicloud_db_instance.main.connection_string
  rds_ro_port              = local.rds_readonly_enabled ? alicloud_db_readonly_instance.read[0].port : alicloud_db_instance.main.port
}
