# Define the elastic IP as an output variable.
output "ip" {
  value = "${aws_eip.ip.public_ip}"
}

# Define the load balancer DNS name as an output variable.
output "lb_dns_name" {
  value = "${aws_alb.alb.dns_name}"
}
