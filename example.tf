terraform {
  backend "consul" {
    address = "172.17.0.2:8500"
    path    = "getting-started-example"
    lock    = true
  }
}

provider "aws" {
  region     = "${var.region}"
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
}

module "child" {
  source = "./child"
  region = "${var.region}"
  availability_zones = "${var.availability_zones}"
  amis = "${var.amis}"
  public_key_path = "${var.public_key_path}"

  rds_instance_identifier = "${var.rds_instance_identifier}"
  database_name = "${var.database_name}"
  database_user = "${var.database_user}"
  database_password = "${var.database_password}"
  certificate_arn = "${var.certificate_arn}"
  route53_hosted_zone_name = "${var.route53_hosted_zone_name}"
  allowed_cidr_blocks = "${var.allowed_cidr_blocks}"
}

output "child_ip" {
  value = "${module.child.ip}"
}

output "child_lb" {
  value = "${module.child.lb_dns_name}"
}
