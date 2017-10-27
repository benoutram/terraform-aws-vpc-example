public_key_path = "/home/ben/.ssh/id_rsa_terraform_test.pub"
region = "eu-west-1"
amis = {
  "eu-west-1" = "ami-ebd02392"
}
rds_instance_identifier = "terraform-mysql"
database_name = "terraform_test_db"
database_user = "terraform"
certificate_arn = "arn:aws:acm:eu-west-1:942044917415:certificate/5d639a80-3bad-4dff-9df2-b2ea1c2350c7"
route53_hosted_zone_name = "benoutram.co.uk."
allowed_cidr_blocks = ["80.2.226.42/32"]
instance_type = "t2.micro"