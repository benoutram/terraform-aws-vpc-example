variable "public_key_path" {}
variable "region" {}
variable "availability_zones" {
  type = "list"
}
variable "amis" {
  type = "map"
}
variable "rds_instance_identifier" {}
variable "database_name" {}
variable "database_password" {}
variable "database_user" {}
variable "certificate_arn" {}
variable "route53_hosted_zone_name" {}
variable "allowed_cidr_blocks" {
  type = "list"
}