locals {
  cr_existing_instance_id  = try(trimspace(var.cr_existing_instance_id), "")
  cr_use_existing_instance = var.cr_enabled && local.cr_existing_instance_id != ""
  cr_create_instance       = var.cr_enabled && !local.cr_use_existing_instance
  cr_instance_id           = local.cr_use_existing_instance ? local.cr_existing_instance_id : try(alicloud_cr_ee_instance.main[0].id, null)

  cr_registry_public_endpoint = try(data.alicloud_cr_ee_instances.selected[0].instances[0].public_endpoints[0], null)
  cr_registry_vpc_endpoint    = try(data.alicloud_cr_ee_instances.selected[0].instances[0].vpc_endpoints[0], null)

  cr_registry_endpoint_for_runtime = var.cr_registry_endpoint_prefer_vpc ? (
    local.cr_registry_vpc_endpoint != null ? local.cr_registry_vpc_endpoint : local.cr_registry_public_endpoint
    ) : (
    local.cr_registry_public_endpoint != null ? local.cr_registry_public_endpoint : local.cr_registry_vpc_endpoint
  )

  cr_registry_has_any_vpc_link = var.cr_enabled && var.cr_link_ack_vpc_endpoint && local.cr_use_existing_instance ? (
    length(try(data.alicloud_cr_vpc_endpoint_linked_vpcs.registry_existing[0].vpc_endpoint_linked_vpcs, [])) > 0
  ) : false
}

resource "random_password" "cr_registry_password" {
  count            = var.cr_enabled ? 1 : 0
  length           = 20
  special          = true
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  override_special = "!#$%*()-_=+[]{}:?"
}

resource "random_string" "cr_instance_name_suffix" {
  count   = var.cr_enabled ? 1 : 0
  length  = 6
  upper   = false
  special = false
}

resource "alicloud_cr_ee_instance" "main" {
  count          = local.cr_create_instance ? 1 : 0
  payment_type   = "Subscription"
  period         = var.cr_period
  renew_period   = var.cr_renew_period
  renewal_status = var.cr_renewal_status
  instance_type  = var.cr_instance_type
  instance_name  = "mhs2-${trimsuffix(substr(local.name_prefix, 0, 17), "-")}-${random_string.cr_instance_name_suffix[0].result}"
  password       = random_password.cr_registry_password[0].result
}

data "alicloud_cr_ee_instances" "selected" {
  count          = var.cr_enabled ? 1 : 0
  ids            = compact([local.cr_instance_id])
  enable_details = true
}

data "alicloud_cr_vpc_endpoint_linked_vpcs" "registry_existing" {
  count = var.cr_enabled && var.cr_link_ack_vpc_endpoint && local.cr_use_existing_instance ? 1 : 0

  instance_id = local.cr_instance_id
  module_name = "Registry"
}

resource "alicloud_cr_vpc_endpoint_linked_vpc" "ack_registry" {
  count = var.cr_enabled && var.cr_link_ack_vpc_endpoint && (!local.cr_use_existing_instance || !local.cr_registry_has_any_vpc_link) ? 1 : 0

  instance_id                      = local.cr_instance_id
  vpc_id                           = alicloud_vpc.main.id
  vswitch_id                       = alicloud_vswitch.ack.id
  module_name                      = "Registry"
  enable_create_dns_record_in_pvzt = var.cr_vpc_endpoint_enable_privatezone_dns
}

data "alicloud_cr_endpoint_acl_service" "internet_registry" {
  count = var.cr_enabled && var.cr_enable_internet_acl_service ? 1 : 0

  instance_id   = local.cr_instance_id
  module_name   = "Registry"
  endpoint_type = "internet"
  enable        = true
}

resource "alicloud_cr_endpoint_acl_policy" "internet_registry" {
  for_each = var.cr_enabled && var.cr_enable_internet_acl_service ? toset(var.cr_internet_acl_entries) : toset([])

  instance_id   = local.cr_instance_id
  module_name   = "Registry"
  endpoint_type = "internet"
  entry         = each.value
  description   = "Managed by Terraform (${local.name_prefix})"

  depends_on = [data.alicloud_cr_endpoint_acl_service.internet_registry]
}

resource "alicloud_cr_ee_namespace" "main" {
  count              = var.cr_enabled ? 1 : 0
  instance_id        = local.cr_instance_id
  name               = var.cr_namespace
  auto_create        = false
  default_visibility = "PRIVATE"
}

resource "alicloud_cr_ee_repo" "moodle" {
  count       = var.cr_enabled ? 1 : 0
  instance_id = local.cr_instance_id
  namespace   = alicloud_cr_ee_namespace.main[0].name
  name        = var.cr_repo_moodle_name
  repo_type   = "PRIVATE"
  summary     = "Moodle image repository"
  detail      = "Terraform-managed repository for Moodle"
}

resource "alicloud_cr_ee_repo" "pgbouncer" {
  count       = var.cr_enabled ? 1 : 0
  instance_id = local.cr_instance_id
  namespace   = alicloud_cr_ee_namespace.main[0].name
  name        = var.cr_repo_pgbouncer_name
  repo_type   = "PRIVATE"
  summary     = "PgBouncer image repository"
  detail      = "Terraform-managed repository for PgBouncer"
}
