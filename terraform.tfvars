key_name = "terraform_test"
public_key_path = "/home/ben/.ssh/id_rsa_terraform_test.pub"
region = "eu-west-1"
availability_zones = ["a", "b", "c"]
amis = {
  "eu-west-1" = "ami-ebd02392"
}

rds_instance_identifier = "terraform-mysql"
database_name = "terraform_test_db"
database_user = "terraform"
