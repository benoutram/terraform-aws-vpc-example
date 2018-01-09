# Create a security group in the VPC which our instances will belong to.
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

# Create a data source from a shell script for provisioning the machine. The variables will be interpolated within the script.
data "template_file" "provision" {
  template = "${file("${path.module}/configs/provision.sh")}"

  vars {
    database_endpoint = "${aws_db_instance.default.endpoint}"
    database_password = "${var.database_password}"
    region            = "${var.region}"
    s3_bucket_name    = "${var.s3_bucket_name}"
  }
}

# Create a new EC2 launch configuration to be used with the autoscaling group.
resource "aws_launch_configuration" "launch_config" {
  name_prefix                 = "terraform-example-web-instance"
  image_id                    = "${lookup(var.amis, var.region)}"
  iam_instance_profile        = "${aws_iam_instance_profile.example_profile.id}"
  instance_type               = "${var.instance_type}"
  key_name                    = "${aws_key_pair.deployer.id}"
  security_groups             = ["${aws_security_group.default.id}"]
  associate_public_ip_address = true
  user_data                   = "${data.template_file.provision.rendered}"

  lifecycle {
    create_before_destroy = true
  }
}

# Create the autoscaling group.
resource "aws_autoscaling_group" "autoscaling_group" {
  launch_configuration = "${aws_launch_configuration.launch_config.id}"
  min_size             = 3
  max_size             = 10
  target_group_arns    = ["${aws_alb_target_group.group.arn}"]
  vpc_zone_identifier  = ["${aws_subnet.main.*.id}"]

  tag {
    key                 = "Name"
    value               = "terraform-example-autoscaling-group"
    propagate_at_launch = true
  }
}
