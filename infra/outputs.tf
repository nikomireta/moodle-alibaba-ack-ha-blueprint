output "region" {
  description = "Deployment region."
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID."
  value       = alicloud_vpc.main.id
}

output "ack_cluster_id" {
  description = "ACK cluster ID."
  value       = alicloud_cs_managed_kubernetes.main.id
}

output "ack_cluster_name" {
  description = "ACK cluster name."
  value       = alicloud_cs_managed_kubernetes.main.name
}

output "ack_effective_instance_types" {
  description = "Effective instance types chosen per ACK node pool."
  value       = local.ack_node_pool_effective_instance_types
}

output "ack_kube_config" {
  description = "Temporary kubeconfig returned by ACK credential data source."
  value       = data.alicloud_cs_cluster_credential.ack.kube_config
  sensitive   = true
}

output "rds_instance_id" {
  description = "RDS primary instance ID."
  value       = alicloud_db_instance.main.id
}

output "rds_readonly_instance_id" {
  description = "RDS readonly instance ID (null when disabled)."
  value       = try(alicloud_db_readonly_instance.read[0].id, null)
}

output "rds_rw_connection_string" {
  description = "RDS read/write private endpoint."
  value       = local.rds_rw_connection_string
}

output "rds_ro_connection_string" {
  description = "RDS read-only endpoint (falls back to RW when readonly disabled)."
  value       = local.rds_ro_connection_string
}

output "rds_account_password" {
  description = "Generated RDS password for Moodle account."
  value       = random_password.moodle_db_password.result
  sensitive   = true
}

output "nas_mount_target_domain" {
  description = "NAS mount target domain for Kubernetes PV."
  value       = alicloud_nas_mount_target.moodle_data.mount_target_domain
}

output "oss_assets_bucket" {
  description = "OSS bucket name for Moodle assets/ObjectFS."
  value       = alicloud_oss_bucket.moodle_assets.bucket
}

output "oss_config_bucket" {
  description = "OSS bucket name for Moodle config artifacts."
  value       = alicloud_oss_bucket.moodle_config.bucket
}

output "objectfs_s3_bucket_effective" {
  description = "Effective ObjectFS S3-compatible bucket used by runtime config."
  value       = local.objectfs_s3_bucket_name_effective
}

output "objectfs_s3_region_effective" {
  description = "Effective ObjectFS S3-compatible region used by runtime config."
  value       = local.objectfs_s3_region_effective
}

output "objectfs_s3_base_url_effective" {
  description = "Effective ObjectFS S3-compatible endpoint URL used by runtime config."
  value       = local.objectfs_s3_base_url_effective
}

output "objectfs_s3_key_prefix_effective" {
  description = "Effective ObjectFS key prefix used by runtime config."
  value       = local.objectfs_s3_key_prefix_normalized
}

output "objectfs_s3_ram_user_name_effective" {
  description = "Generated ObjectFS RAM username when non-SDK credential mode is enabled."
  value       = local.objectfs_s3_ram_user_name_effective
}

output "cr_instance_id" {
  description = "CR EE instance ID (null when cr_enabled=false)."
  value       = local.cr_instance_id
}

output "cr_registry_username" {
  description = "CR registry login username when available."
  value       = try(data.alicloud_cr_ee_instances.selected[0].instances[0].temp_username, null)
  sensitive   = true
}

output "cr_registry_password" {
  description = "CR registry login password/token when available."
  value = var.cr_enabled ? coalesce(
    try(data.alicloud_cr_ee_instances.selected[0].instances[0].authorization_token, null),
    try(random_password.cr_registry_password[0].result, null)
  ) : null
  sensitive = true
}

output "cr_registry_public_endpoint" {
  description = "CR public registry endpoint (null when CR disabled)."
  value       = local.cr_registry_public_endpoint
}

output "cr_registry_vpc_endpoint" {
  description = "CR VPC registry endpoint if available (null when not configured/disabled)."
  value       = local.cr_registry_vpc_endpoint
}

output "cr_registry_endpoint_for_runtime" {
  description = "Preferred registry endpoint for runtime pulls (VPC first when enabled)."
  value       = local.cr_registry_endpoint_for_runtime
}

output "cr_registry_endpoint_for_push" {
  description = "Preferred registry endpoint for pushes from developer machine (public first, fallback runtime endpoint)."
  value       = coalesce(local.cr_registry_public_endpoint, local.cr_registry_endpoint_for_runtime)
}

output "cr_vpc_link_id" {
  description = "ACR Registry module VPC link resource ID."
  value       = try(alicloud_cr_vpc_endpoint_linked_vpc.ack_registry[0].id, null)
}

output "cr_vpc_link_status" {
  description = "ACR Registry module VPC link status."
  value       = try(alicloud_cr_vpc_endpoint_linked_vpc.ack_registry[0].status, null)
}

output "cr_existing_vpc_link_count" {
  description = "Number of existing ACR Registry VPC links detected for reused instance."
  value       = try(length(data.alicloud_cr_vpc_endpoint_linked_vpcs.registry_existing[0].vpc_endpoint_linked_vpcs), 0)
}

output "cr_existing_ack_vpc_link_count" {
  description = "Number of existing ACR Registry VPC links matching the stack VPC."
  value       = length(local.cr_registry_has_ack_vpc_link ? [1] : [])
}

output "moodle_www_root_configured" {
  description = "Configured Moodle public URL in runtime secret."
  value       = var.moodle_www_root
}

output "runtime_service_hint" {
  description = "Quick command to inspect Moodle service endpoint after runtime deploy."
  value       = "kubectl -n moodle get svc moodle-svc"
}
