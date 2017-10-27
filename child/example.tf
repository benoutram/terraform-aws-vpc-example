# Create a key pair that will be assigned to our instance.
resource "aws_key_pair" "deployer" {
  key_name   = "terraform_deployer"
  public_key = "${file(var.public_key_path)}"
}

# Create a VPC to launch our instance into.
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags {
    Name = "terraform-example-vpc"
  }
}

# Create an internet gateway to give our subnet access to the outside world.
resource "aws_internet_gateway" "gateway" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags {
    Name = "terraform-example-internet-gateway"
  }
}

# Grant the VPC internet access on its main route table.
resource "aws_route" "route" {
  route_table_id         = "${aws_vpc.vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gateway.id}"
}

# Create subnets in each availability zone to launch our instances into, each with address blocks within the VPC.
resource "aws_subnet" "main" {
  count                   = "${length(var.availability_zones)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}${element(var.availability_zones, count.index)}"
  tags {
    Name = "public-${var.region}${element(var.availability_zones, count.index)}"
  }
}

# Create subnets in each availability zone for RDS, each with address blocks within the VPC.
resource "aws_subnet" "rds" {
  count                   = "${length(var.availability_zones)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block              = "10.0.${length(var.availability_zones) + count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}${element(var.availability_zones, count.index)}"
  tags {
    Name = "rds-${var.region}${element(var.availability_zones, count.index)}"
  }
}

# Create a subnet group with all of our RDS subnets. The group will be applied to the database instance.  
resource "aws_db_subnet_group" "default" {
  name        = "${var.rds_instance_identifier}-subnet-group"
  description = "Terraform example RDS subnet group"
  subnet_ids  = ["${aws_subnet.rds.*.id}"]
}

# Create a security group in the VPC which our instance will belong to.
resource "aws_security_group" "default" {
  name        = "terraform_security_group"
  description = "Terraform example security group"
  vpc_id      = "${aws_vpc.vpc.id}"

  # Restrict inboud SSH traffic by IP address.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = "${var.allowed_cidr_blocks}"
  }

  # Restrict inbound HTTP traffic to the load balancer.
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = ["${aws_security_group.alb.id}"]
  }

  # Allow outbound internet access.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "terraform-example-security-group"
  }
}

# Create a RDS security group in the VPC which our database will belong to.
resource "aws_security_group" "rds" {  
  name = "terraform_rds_security_group"
  description = "RDS Mysql server (terraform-managed)"
  vpc_id = "${aws_vpc.vpc.id}"

  # Keep the instance private by only allowing traffic from the web server.
  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = ["${aws_security_group.default.id}"]
  }

  # Allow all outbound traffic.
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "terraform-example-rds-security-group"
  }
}

# Create an application load balancer security group.
resource "aws_security_group" "alb" {
  name        = "terraform_alb_security_group"
  description = "Terraform load balancer security group"
  vpc_id      = "${aws_vpc.vpc.id}"
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = "${var.allowed_cidr_blocks}"
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "terraform-example-alb-security-group"
  }
}

# Create a profile for the S3 access role that will passed to the EC2 instance when it starts.
resource "aws_iam_instance_profile" "example_profile" {
  name  = "terraform_instance_profile"
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

# Attach a policy to the S3 access role with permissions to list and retrieve objects in the code bucket.
resource "aws_iam_role_policy" "s3_code_bucket_access_policy" {
  name = "s3_code_bucket_access_policy"
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
data "template_file" "springboot_conf" {
  template = "${file("${path.module}/configs/spring-boot/springboot-s3-example.conf")}"

  vars {
    database_endpoint = "${aws_db_instance.default.endpoint}",
    database_password = "${var.database_password}"
  }
}

# Create an EC2 instance in the VPC in the first subnet.
resource "aws_instance" "instance" {
  ami                    = "${lookup(var.amis, var.region)}"
  iam_instance_profile   = "${aws_iam_instance_profile.example_profile.id}"
  instance_type          = "t2.micro"
  key_name               = "${aws_key_pair.deployer.id}"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  subnet_id              = "${aws_subnet.main.0.id}"

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
    source      = "${path.module}/configs/nginx/nginx.conf"
    destination = "/home/ec2-user/nginx.conf"

    connection {
      user = "ec2-user"
    }
  }

  # Copy our Nginx site config to redirect port 80 to 8080.
  provisioner "file" {
    source      = "${path.module}/configs/nginx/springboot-s3-example-nginx.conf"
    destination = "/home/ec2-user/springboot-s3-example-nginx.conf"

    connection {
      user = "ec2-user"
    }
  }

  # Copy our Spring Boot run arguments.
  provisioner "file" {
    content     = "${data.template_file.springboot_conf.rendered}"
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
      "sudo mv /home/ec2-user/springboot-s3-example-nginx.conf /etc/nginx/conf.d/springboot-s3-example-nginx.conf",
      "sudo chown root:root /etc/nginx/conf.d/springboot-s3-example-nginx.conf",
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

  tags {
    Name = "terraform-example-web-instance"
  }
}

# Create an elastic IP for our instance.
resource "aws_eip" "ip" {
  instance = "${aws_instance.instance.id}"
}

# Create a RDS Mysql database instance in the VPC with our RDS subnet group and security group.
resource "aws_db_instance" "default" {
  identifier                = "${var.rds_instance_identifier}"
  allocated_storage         = 5
  engine                    = "mysql"
  engine_version            = "5.6.35"
  instance_class            = "db.t2.micro"
  name                      = "${var.database_name}"
  username                  = "${var.database_user}"
  password                  = "${var.database_password}"
  db_subnet_group_name      = "${aws_db_subnet_group.default.id}"
  vpc_security_group_ids    = ["${aws_security_group.rds.id}"]
  skip_final_snapshot       = true
  final_snapshot_identifier = "Ignore"
}

# Manage the MySQL configuration by creating a parameter group.
resource "aws_db_parameter_group" "default" {
  name        = "${var.rds_instance_identifier}-param-group"
  description = "Terraform example parameter group for mysql5.6"
  family      = "mysql5.6"

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }
}

# Create a new application load balancer.
resource "aws_alb" "alb" {
  name            = "terraform-example-alb"
  security_groups = ["${aws_security_group.alb.id}"]
  subnets         = ["${aws_subnet.main.*.id}"]

  tags {
    Name = "terraform-example-alb"
  }
}

# Create a new target group for the application load balancer.
resource "aws_alb_target_group" "group" {
  name     = "terraform-example-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.vpc.id}"

  # Alter the destination of the health check to be the login page.
  health_check {
    path = "/login"
    port = 80
  }
}

# Register the instance in the target group.
resource "aws_alb_target_group_attachment" "instance" {
  target_group_arn = "${aws_alb_target_group.group.arn}"
  target_id        = "${aws_instance.instance.id}"
}

# Create a new application load balancer listener.
resource "aws_alb_listener" "listener" {
  load_balancer_arn = "${aws_alb.alb.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "${var.certificate_arn}"

  default_action {
    target_group_arn = "${aws_alb_target_group.group.arn}"
    type             = "forward"
  }
}

# Provide details about our Route53 hosted zone.
data "aws_route53_zone" "zone" {
  name = "${var.route53_hosted_zone_name}"
}

# Define a record set in Route 53 for the load balancer.
resource "aws_route53_record" "terraform" {
  zone_id = "${data.aws_route53_zone.zone.zone_id}"
  name    = "terraform.benoutram.co.uk"
  type    = "A"

  alias {
    name                   = "${aws_alb.alb.dns_name}"
    zone_id                = "${aws_alb.alb.zone_id}"
    evaluate_target_health = true
  }
}

# Define the elastic IP as an output variable which will be propagated up to the client of this module.
output "ip" {
  value = "${aws_eip.ip.public_ip}"
}

# Define the load balancer DNS name as an output variable which will be propagated up to the client of this module.
output "lb_dns_name" {
  value = "${aws_alb.alb.dns_name}"
}