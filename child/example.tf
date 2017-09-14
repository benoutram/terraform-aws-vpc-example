resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  tags {
    Name = "Terraform example"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  count                   = "${length(var.availability_zones)}"
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}${element(var.availability_zones, count.index)}"
  tags {
    Name = "Public ${var.region}${element(var.availability_zones, count.index)}"
  }
}

resource "aws_subnet" "rds" {
  count                   = "${length(var.availability_zones)}"
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.${length(var.availability_zones) + count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}${element(var.availability_zones, count.index)}"
  tags {
    Name = "RDS ${var.region}${element(var.availability_zones, count.index)}"
  }
}

resource "aws_security_group" "default" {
  name        = "terraform_example"
  description = "Terraform example security group"
  vpc_id     = "${aws_vpc.default.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["80.2.226.42/32"]
  }

  # HTTP access from the VPC
  #ingress {
  #  from_port   = 80
  #  to_port     = 80
  #  protocol    = "tcp"
  #  cidr_blocks = ["10.0.0.0/16"]
  #}

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "example" {
  ami           = "${lookup(var.amis, var.region)}"
  instance_type = "t2.micro"
  key_name      = "${aws_key_pair.auth.id}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id = "${aws_subnet.default.0.id}"

  provisioner "remote-exec" {
    inline = [
      "sudo yum update",
      "sudo yum install nginx -y",
      "sudo yum install java-1.8.0-openjdk-devel -y",
      "sudo yum remove java-1.7.0-openjdk -y"
    ]
  }

  provisioner "file" {
    source = "${path.module}/configs/nginx/your-domain-name.conf"
    destination = "/etc/nginx/conf.d/your-domain-name.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo service nginx start"
    ]
  }
}

resource "aws_eip" "ip" {
  instance = "${aws_instance.example.id}"
}

output "ip" {
  value = "${aws_eip.ip.public_ip}"
}

# Create a database server
resource "aws_db_instance" "default" {
  identifier                = "${var.rds_instance_identifier}"
  allocated_storage         = 5
  engine                    = "mysql"
  engine_version            = "5.7.17"
  instance_class            = "db.t2.micro"
  name                      = "${var.database_name}"
  username                  = "${var.database_user}"
  password                  = "${var.database_password}"
  db_subnet_group_name      = "${aws_db_subnet_group.db_subnet_group.id}"
  vpc_security_group_ids    = ["${aws_security_group.db_access.id}"]
  skip_final_snapshot       = true
  final_snapshot_identifier = "Ignore"
}

# Configure the MySQL provider based on the outcome of
# creating the aws_db_instance.
provider "mysql" {
  endpoint = "${aws_db_instance.default.endpoint}"
  username = "${aws_db_instance.default.username}"
  password = "${aws_db_instance.default.password}"
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "${var.rds_instance_identifier}-subnetgrp"
  description = "RDS subnet group"
  subnet_ids  = ["${aws_subnet.rds.*.id}"] 
}

resource "aws_security_group" "db_access" {  
  name = "terraform_test_db"
  description = "RDS Mysql server (terraform-managed)"
  vpc_id = "${aws_vpc.default.id}"

  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow all outbound traffic.
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_parameter_group" "default" {
  name   = "${var.rds_instance_identifier}-pg"
  family = "mysql5.7"

  parameter {
    name = "character_set_server"
    value = "utf8"
  }

  parameter {
    name = "character_set_client"
    value = "utf8"
  }
}
