resource "random_password" "ack_node_login" {
  length           = 20
  special          = true
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  override_special = "!#$%*()-_=+[]{}:?"
}

locals {
  ack_node_pools_base = lookup(local.settings, "ack_node_pools", {})
  ack_node_pools = {
    for pool_name, pool in local.ack_node_pools_base :
    pool_name => merge(pool, try(var.ack_node_pool_size_overrides[pool_name], {}))
  }

  ack_node_pool_autoscaling_enabled = {
    for pool_name, pool in local.ack_node_pools :
    pool_name => (var.ack_enable_nodepool_autoscaling && lookup(pool, "enable_autoscaling", false))
  }

  ack_node_pool_available_requested_instance_types = {
    for pool_name, pool in local.ack_node_pools :
    pool_name => [
      for instance_type in lookup(pool, "instance_types", []) :
      instance_type if contains(try(data.alicloud_instance_types.ack_worker_pool[pool_name].ids, []), instance_type)
    ]
  }

  ack_node_pool_discovered_instance_types = {
    for pool_name, pool in local.ack_node_pools :
    pool_name => [
      for instance_type in try(data.alicloud_instance_types.ack_worker_pool[pool_name].instance_types, []) :
      instance_type.id
      if(
        (try(lookup(pool, "min_cpu_core_count", null), null) == null || instance_type.cpu_core_count >= lookup(pool, "min_cpu_core_count", 0))
        &&
        (try(lookup(pool, "min_memory_size_gb", null), null) == null || instance_type.memory_size >= lookup(pool, "min_memory_size_gb", 0))
      )
    ]
  }

  ack_node_pool_candidate_instance_types = {
    for pool_name, pool in local.ack_node_pools :
    pool_name => distinct(concat(
      local.ack_node_pool_available_requested_instance_types[pool_name],
      local.ack_node_pool_discovered_instance_types[pool_name]
    ))
  }

  ack_node_pool_effective_instance_types = {
    for pool_name, pool in local.ack_node_pools :
    pool_name => slice(
      local.ack_node_pool_candidate_instance_types[pool_name],
      0,
      min(var.ack_instance_type_fallback_max_count, length(local.ack_node_pool_candidate_instance_types[pool_name]))
    )
  }

  ack_pod_vswitch_ids = (
    var.ack_pod_vswitch_ids != null && length(var.ack_pod_vswitch_ids) > 0
  ) ? var.ack_pod_vswitch_ids : [alicloud_vswitch.ack.id]
}

data "alicloud_instance_types" "ack_worker_pool" {
  for_each = local.ack_node_pools

  availability_zone                       = alicloud_vswitch.ack.zone_id
  kubernetes_node_role                    = "Worker"
  instance_charge_type                    = lookup(each.value, "instance_charge_type", "PostPaid")
  spot_strategy                           = lookup(each.value, "spot_strategy", "NoSpot")
  system_disk_category                    = lookup(each.value, "system_disk_category", var.ack_default_system_disk_category)
  minimum_eni_private_ip_address_quantity = lookup(each.value, "minimum_eni_private_ip_address_quantity", var.ack_minimum_eni_private_ip_address_quantity)
}

resource "alicloud_cs_managed_kubernetes" "main" {
  name                           = local.name_prefix
  profile                        = var.ack_cluster_profile
  cluster_spec                   = var.ack_cluster_spec
  version                        = var.ack_kubernetes_version
  vswitch_ids                    = [alicloud_vswitch.ack.id]
  pod_vswitch_ids                = local.ack_pod_vswitch_ids
  new_nat_gateway                = var.ack_new_nat_gateway
  proxy_mode                     = var.ack_proxy_mode
  service_cidr                   = var.ack_service_cidr
  slb_internet_enabled           = var.ack_api_public_enabled
  deletion_protection            = var.ack_deletion_protection
  skip_set_certificate_authority = true
  tags                           = local.common_tags

  dynamic "addons" {
    for_each = var.ack_cluster_addons
    content {
      name     = addons.value.name
      config   = try(addons.value.config, null)
      disabled = try(addons.value.disabled, false)
    }
  }
}

resource "alicloud_cs_kubernetes_node_pool" "pool" {
  for_each = local.ack_node_pools

  node_pool_name       = substr("${local.name_prefix}-${each.key}", 0, 63)
  cluster_id           = alicloud_cs_managed_kubernetes.main.id
  vswitch_ids          = [alicloud_vswitch.ack.id]
  instance_types       = local.ack_node_pool_effective_instance_types[each.key]
  instance_charge_type = lookup(each.value, "instance_charge_type", "PostPaid")
  spot_strategy        = lookup(each.value, "spot_strategy", "NoSpot")
  desired_size         = local.ack_node_pool_autoscaling_enabled[each.key] ? null : lookup(each.value, "desired_size", 0)
  password             = random_password.ack_node_login.result
  system_disk_category = lookup(each.value, "system_disk_category", var.ack_default_system_disk_category)
  system_disk_size     = lookup(each.value, "system_disk_size", var.ack_default_system_disk_size)
  tags                 = local.common_tags

  dynamic "scaling_config" {
    for_each = local.ack_node_pool_autoscaling_enabled[each.key] ? [1] : []
    content {
      enable   = true
      min_size = lookup(each.value, "min_size", lookup(each.value, "desired_size", 0))
      max_size = lookup(each.value, "max_size", lookup(each.value, "desired_size", 0))
      type     = lookup(each.value, "scaling_type", "cpu")
    }
  }

  dynamic "labels" {
    for_each = lookup(each.value, "labels", {})
    content {
      key   = labels.key
      value = labels.value
    }
  }

  dynamic "taints" {
    for_each = lookup(each.value, "taints", [])
    content {
      key    = taints.value.key
      value  = try(taints.value.value, null)
      effect = taints.value.effect
    }
  }

  lifecycle {
    ignore_changes = [
      instance_types
    ]

    precondition {
      condition     = length(local.ack_node_pool_effective_instance_types[each.key]) > 0
      error_message = "No authorized/in-stock ACK instance type available for node pool in selected zone. Set availability_zone_id and/or explicit instance_types."
    }
  }
}
