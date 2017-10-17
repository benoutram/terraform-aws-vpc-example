# Create a key pair that will be assigned to our instance.
resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

# Create a VPC to launch our instance into.
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  tags {
    Name = "Terraform example"
  }
}

# Create an internet gateway to give our subnet access to the outside world.
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

# Grant the VPC internet access on its main route table.
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create subnets for each availability zone to launch our instances into, each with address blocks within the VPC.
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

# Create subnets in each availability zone for RDS.
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

# Create a security group in our non-default VPC which our instance will belong to.
resource "aws_security_group" "default" {
  name        = "terraform_example"
  description = "Terraform example security group"
  vpc_id     = "${aws_vpc.default.id}"

  # Restrict inboud SSH traffic by IP address.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["80.2.226.42/32"]
  }

  # Restrict inbound HTTP traffic by IP address.
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["80.2.226.42/32"]
  }

  # HTTP access from the VPC (private access not required yet, since no other instances).
  #ingress {
  #  from_port   = 80
  #  to_port     = 80
  #  protocol    = "tcp"
  #  cidr_blocks = ["10.0.0.0/16"]
  #}

  # Allow outbound internet access.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a profile for the S3 access role that will passed to the EC2 instance when it starts.
resource "aws_iam_instance_profile" "example_instance_profile" {
  name  = "example_instance_profile"
  role = "${aws_iam_role.s3_access_role.name}"
}

# Create the S3 access role with an inline policy allowing the AWS CLI to assume roles.
resource "aws_iam_role" "s3_access_role" {
  name = "s3_access_role"
  path = "/"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

# Attach a policy to the role with S3 access permissions for the example buckeit.
resource "aws_iam_role_policy" "web_iam_role_policy" {
  name = "web_iam_role_policy"
  role = "${aws_iam_role.s3_access_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::springboot-s3-example"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": ["arn:aws:s3:::springboot-s3-example/*"]
    }
  ]
}
EOF
}

/* Create a data source from a template file for Spring Boot run arguments. The variables will be interpolated within the template.
   The Spring Boot database URL will be the endpoint of the database instance.*/
data "template_file" "springboot-conf" {
  template = "${file("${path.module}/configs/spring-boot/springboot-s3-example.conf")}"

  vars {
    database_endpoint = "${aws_db_instance.default.endpoint}",
    database_password = "${var.database_password}"
  }
}

# Create the EC2 instance in our non-default VPC in the first subnet.
resource "aws_instance" "example" {
  ami                    = "${lookup(var.amis, var.region)}"
  iam_instance_profile   = "${aws_iam_instance_profile.example_instance_profile.id}"
  instance_type          = "t2.micro"
  key_name               = "${aws_key_pair.auth.id}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id              = "${aws_subnet.default.0.id}"

  /* Invoke the provision script after the resource is created
     Installs Nginx, Java 8, copies the Spring Boot application from S3 and installs it as an init.d service */
  provisioner "remote-exec" {
    script = "${path.module}/configs/provision.sh"

    connection {
      user = "ec2-user"
    }
  }

  # Copy the Nginx config to disable the default site.
  provisioner "file" {
    source = "${path.module}/configs/nginx/nginx.conf"
    destination = "/home/ec2-user/nginx.conf"

    connection {
      user = "ec2-user"
    }
  }

  # Copy our Nginx site config to redirect port 80 to 8080.
  provisioner "file" {
    source = "${path.module}/configs/nginx/your-domain-name.conf"
    destination = "/home/ec2-user/your-domain-name.conf"

    connection {
      user = "ec2-user"
    }
  }

  # Copy our Spring Boot run arguments.
  provisioner "file" {
    content     = "${data.template_file.springboot-conf.rendered}"
    destination = "/home/ec2-user/springboot-s3-example.conf"

    connection {
      user = "ec2-user"
    }
  }

  /* Move files into position.
     This is necessary since the files were uploaded as ec2-user, not root.
     Start the Nginx and Spring Boot services */
  provisioner "remote-exec" {
    inline = [
      "sudo mv /home/ec2-user/nginx.conf /etc/nginx/nginx.conf",
      "sudo chown root:root /etc/nginx/nginx.conf",
      "sudo mv /home/ec2-user/your-domain-name.conf /etc/nginx/conf.d/your-domain-name.conf",
      "sudo chown root:root /etc/nginx/conf.d/your-domain-name.conf",
      "sudo mv /home/ec2-user/springboot-s3-example.conf /opt/springboot-s3-example/springboot-s3-example.conf",
      "sudo chmod 400 /opt/springboot-s3-example/springboot-s3-example.conf",
      "sudo chown springboot:springboot /opt/springboot-s3-example/springboot-s3-example.conf",
      "sudo service nginx start",
      "sudo service springboot-s3-example start"
    ]

    connection {
      user = "ec2-user"
    }
  }
}

# Create an elastic IP for our instance.
resource "aws_eip" "ip" {
  instance = "${aws_instance.example.id}"
}

# Define the elastic IP as an output variable which will be propagated up to the client of this module.
output "ip" {
  value = "${aws_eip.ip.public_ip}"
}

# Create an RDS Mysql database instance in our non default VPC with our RDS subnet group.
resource "aws_db_instance" "default" {
  identifier                = "${var.rds_instance_identifier}"
  allocated_storage         = 5
  engine                    = "mysql"
  engine_version            = "5.6.35"
  instance_class            = "db.t2.micro"
  name                      = "${var.database_name}"
  username                  = "${var.database_user}"
  password                  = "${var.database_password}"
  db_subnet_group_name      = "${aws_db_subnet_group.db_subnet_group.id}"
  vpc_security_group_ids    = ["${aws_security_group.db_access.id}"]
  skip_final_snapshot       = true
  final_snapshot_identifier = "Ignore"
}

# Configure the MySQL provider based on the outcome of creating the aws_db_instance.
provider "mysql" {
  endpoint = "${aws_db_instance.default.endpoint}"
  username = "${aws_db_instance.default.username}"
  password = "${aws_db_instance.default.password}"
}

# Create the subnet group with all of our RDS subnets. The group will be applied to the database instance.  
resource "aws_db_subnet_group" "db_subnet_group" {
  name        = "${var.rds_instance_identifier}-subnetgrp"
  description = "RDS subnet group"
  subnet_ids  = ["${aws_subnet.rds.*.id}"] 
}

# Create an RDS security group for our non default VPC.
resource "aws_security_group" "db_access" {  
  name = "terraform_test_db"
  description = "RDS Mysql server (terraform-managed)"
  vpc_id = "${aws_vpc.default.id}"

  # Keep the instance private by only allowing traffic from the web server.
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

# Manage the MySQL configuration by creating a parameter group
resource "aws_db_parameter_group" "default" {
  name   = "${var.rds_instance_identifier}-pg"
  family = "mysql5.6"

  parameter {
    name = "character_set_server"
    value = "utf8"
  }

  parameter {
    name = "character_set_client"
    value = "utf8"
  }
}
