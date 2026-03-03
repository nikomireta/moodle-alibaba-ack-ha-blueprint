resource "random_string" "oss" {
  length  = 6
  upper   = false
  special = false
}

locals {
  moodle_assets_bucket_name = coalesce(
    var.oss_assets_bucket_name,
    substr(replace("${local.name_prefix}-${var.oss_assets_bucket_name_prefix}-${random_string.oss.result}", "_", "-"), 0, 63)
  )

  moodle_config_bucket_name = coalesce(
    var.oss_config_bucket_name,
    substr(replace("${local.name_prefix}-${var.oss_config_bucket_name_prefix}-${random_string.oss.result}", "_", "-"), 0, 63)
  )

  objectfs_s3_region_effective = coalesce(var.objectfs_s3_region, var.region)
  objectfs_s3_base_url_effective = coalesce(
    var.objectfs_s3_base_url,
    "https://oss-${local.objectfs_s3_region_effective}-internal.aliyuncs.com"
  )
  objectfs_s3_bucket_name_effective = coalesce(var.objectfs_s3_bucket_name, local.moodle_assets_bucket_name)
  objectfs_s3_key_prefix_effective  = trimspace(var.objectfs_s3_key_prefix)
  objectfs_s3_key_prefix_normalized = local.objectfs_s3_key_prefix_effective == "" ? "" : "${trimsuffix(local.objectfs_s3_key_prefix_effective, "/")}/"
  objectfs_s3_static_credentials    = var.objectfs_s3_access_key != null && var.objectfs_s3_secret != null
  objectfs_s3_manage_ram_credentials = (
    var.objectfs_s3_enabled
    && !var.objectfs_s3_use_sdk_creds
    && !local.objectfs_s3_static_credentials
    && var.objectfs_s3_create_ram_credentials
  )

  objectfs_s3_ram_user_name_base      = coalesce(var.objectfs_s3_ram_user_name, "${local.name_prefix}-objectfs-${random_string.oss.result}")
  objectfs_s3_ram_user_name_effective = substr(replace(lower(local.objectfs_s3_ram_user_name_base), "/[^0-9a-z._-]/", "-"), 0, 64)
  objectfs_s3_policy_name             = substr(replace(lower("${local.name_prefix}-objectfs-s3-${random_string.oss.result}"), "/[^0-9a-z-]/", "-"), 0, 128)

  objectfs_s3_bucket_resource_arn = "acs:oss:*:*:${local.objectfs_s3_bucket_name_effective}"
  objectfs_s3_object_resource_arn = local.objectfs_s3_key_prefix_normalized == "" ? (
    "${local.objectfs_s3_bucket_resource_arn}/*"
    ) : (
    "${local.objectfs_s3_bucket_resource_arn}/${local.objectfs_s3_key_prefix_normalized}*"
  )
}

resource "alicloud_oss_bucket" "moodle_assets" {
  bucket        = local.moodle_assets_bucket_name
  storage_class = "Standard"
  force_destroy = var.oss_force_destroy
  tags          = local.common_tags
}

resource "alicloud_oss_bucket_acl" "moodle_assets" {
  bucket = alicloud_oss_bucket.moodle_assets.bucket
  acl    = "private"
}

resource "alicloud_oss_bucket" "moodle_config" {
  bucket        = local.moodle_config_bucket_name
  storage_class = "Standard"
  force_destroy = var.oss_force_destroy
  tags          = local.common_tags
}

resource "alicloud_oss_bucket_acl" "moodle_config" {
  bucket = alicloud_oss_bucket.moodle_config.bucket
  acl    = "private"
}

resource "alicloud_nas_file_system" "moodle_data" {
  protocol_type    = "NFS"
  storage_type     = var.nas_storage_type
  file_system_type = var.nas_file_system_type
  description      = "${local.name_prefix}-moodle-data"
  zone_id          = local.selected_zone_id
  tags             = local.common_tags
}

resource "alicloud_nas_access_group" "moodle_data" {
  access_group_name = coalesce(var.nas_access_group_name, substr("${local.name_prefix}-nasag", 0, 64))
  access_group_type = "Vpc"
  file_system_type  = var.nas_file_system_type
  description       = substr("${local.name_prefix}-nas-access-group", 0, 100)
}

resource "alicloud_nas_access_rule" "moodle_data" {
  access_group_name = alicloud_nas_access_group.moodle_data.access_group_name
  file_system_type  = var.nas_file_system_type
  source_cidr_ip    = var.vpc_cidr
  rw_access_type    = var.nas_rw_access_type
  user_access_type  = var.nas_user_access_type
  priority          = var.nas_access_rule_priority
}

resource "alicloud_nas_mount_target" "moodle_data" {
  file_system_id    = alicloud_nas_file_system.moodle_data.id
  access_group_name = alicloud_nas_access_group.moodle_data.access_group_name
  vswitch_id        = alicloud_vswitch.nas.id
  vpc_id            = alicloud_vpc.main.id
  network_type      = "Vpc"
  security_group_id = alicloud_security_group.ack_nodes.id
}

resource "alicloud_ram_user" "objectfs_s3" {
  count = local.objectfs_s3_manage_ram_credentials ? 1 : 0

  name         = local.objectfs_s3_ram_user_name_effective
  display_name = local.objectfs_s3_ram_user_name_effective
  comments     = "ObjectFS S3 runtime user for ${local.name_prefix}"
  force        = true
}

resource "alicloud_ram_policy" "objectfs_s3" {
  count = local.objectfs_s3_manage_ram_credentials ? 1 : 0

  policy_name = local.objectfs_s3_policy_name
  description = "ObjectFS S3 runtime policy for ${local.name_prefix}"
  force       = true
  tags        = local.common_tags

  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "oss:ListObjects"
        ]
        Resource = [
          local.objectfs_s3_bucket_resource_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "oss:GetObject",
          "oss:PutObject",
          "oss:DeleteObject"
        ]
        Resource = [
          local.objectfs_s3_object_resource_arn
        ]
      }
    ]
  })
}

resource "alicloud_ram_user_policy_attachment" "objectfs_s3" {
  count = local.objectfs_s3_manage_ram_credentials ? 1 : 0

  policy_name = alicloud_ram_policy.objectfs_s3[0].policy_name
  policy_type = alicloud_ram_policy.objectfs_s3[0].type
  user_name   = alicloud_ram_user.objectfs_s3[0].name
}

resource "alicloud_ram_access_key" "objectfs_s3" {
  count = local.objectfs_s3_manage_ram_credentials ? 1 : 0

  user_name = alicloud_ram_user.objectfs_s3[0].name
  status    = "Active"
}
