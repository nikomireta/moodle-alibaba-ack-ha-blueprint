locals {
  rds_selected_zone_id = coalesce(
    var.rds_availability_zone_id,
    try(data.alicloud_db_zones.rds.zones[0].id, null),
    local.selected_zone_id
  )
}

resource "alicloud_vpc" "main" {
  vpc_name    = local.name_prefix
  cidr_block  = var.vpc_cidr
  description = "Moodle high-scale VPC (${var.moodle_environment})"
  tags        = local.common_tags
}

resource "alicloud_vswitch" "ack" {
  vpc_id       = alicloud_vpc.main.id
  zone_id      = local.selected_zone_id
  cidr_block   = var.ack_vswitch_cidr
  vswitch_name = "${local.name_prefix}-ack"
  description  = "ACK workload subnet"
  tags         = local.common_tags
}

resource "alicloud_vswitch" "db" {
  vpc_id       = alicloud_vpc.main.id
  zone_id      = local.rds_selected_zone_id
  cidr_block   = var.db_vswitch_cidr
  vswitch_name = "${local.name_prefix}-db"
  description  = "RDS subnet"
  tags         = local.common_tags
}

resource "alicloud_vswitch" "nas" {
  vpc_id       = alicloud_vpc.main.id
  zone_id      = local.selected_zone_id
  cidr_block   = var.nas_vswitch_cidr
  vswitch_name = "${local.name_prefix}-nas"
  description  = "NAS mount target subnet"
  tags         = local.common_tags
}

resource "alicloud_security_group" "ack_nodes" {
  vpc_id              = alicloud_vpc.main.id
  security_group_name = substr("${local.name_prefix}-ack-sg", 0, 128)
  description         = "Security group for ACK worker nodes"
  tags                = local.common_tags
}

resource "alicloud_security_group_rule" "ack_nodes_ingress_vpc" {
  type              = "ingress"
  ip_protocol       = "all"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "-1/-1"
  priority          = 1
  security_group_id = alicloud_security_group.ack_nodes.id
  cidr_ip           = var.vpc_cidr
}

resource "alicloud_security_group_rule" "ack_nodes_egress_all" {
  type              = "egress"
  ip_protocol       = "all"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "-1/-1"
  priority          = 1
  security_group_id = alicloud_security_group.ack_nodes.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_security_group" "rds" {
  vpc_id              = alicloud_vpc.main.id
  security_group_name = substr("${local.name_prefix}-rds-sg", 0, 128)
  description         = "Security group for RDS PostgreSQL"
  tags                = local.common_tags
}

resource "alicloud_security_group_rule" "rds_ingress_postgres" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "5432/5432"
  priority          = 1
  security_group_id = alicloud_security_group.rds.id
  cidr_ip           = var.vpc_cidr
}

resource "alicloud_security_group_rule" "rds_egress_all" {
  type              = "egress"
  ip_protocol       = "all"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "-1/-1"
  priority          = 1
  security_group_id = alicloud_security_group.rds.id
  cidr_ip           = "0.0.0.0/0"
}
