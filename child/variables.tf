variable "key_name" {}
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
