variable "access_key" {}
variable "secret_key" {}
variable "region" {}
variable "amis" {
  type = "map"
}
variable "availability_zones" {
  type = "list"
}
variable "key_name" {}
variable "public_key_path" {}

variable "rds_instance_identifier" {}
variable "database_name" {}
variable "database_password" {}
variable "database_user" {}
