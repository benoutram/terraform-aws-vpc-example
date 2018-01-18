# Create a data source for our Route53 hosted zone.
data "aws_route53_zone" "zone" {
  name = "${var.route53_hosted_zone_name}"
}

# Create a data source for the availability zones.
data "aws_availability_zones" "available" {}

# Create a data source from a shell script for provisioning the machine. The variables will be interpolated within the script.
data "template_file" "provision" {
  template = "${file("${path.module}/provision.sh")}"

  vars {
    database_endpoint = "${aws_db_instance.default.endpoint}"
    database_name     = "${var.database_name}"
    database_password = "${var.database_password}"
    region            = "${var.region}"
    s3_bucket_name    = "${var.s3_bucket_name}"
  }
}
