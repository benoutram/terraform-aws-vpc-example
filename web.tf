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
