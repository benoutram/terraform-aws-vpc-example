# Create a data source for our Route53 hosted zone.
data "aws_route53_zone" "zone" {
  name = "${var.route53_hosted_zone_name}"
}

# Create a data source for the availability zones.
data "aws_availability_zones" "available" {}
