# Terraform AWS VPC Example #

[![GitHub issues](https://img.shields.io/github/issues/benoutram/terraform-aws-vpc-example.svg)](https://github.com/benoutram/terraform-aws-vpc-example/issues)

[![GitHub forks](https://img.shields.io/github/forks/benoutram/terraform-aws-vpc-example.svg)](https://github.com/benoutram/terraform-aws-vpc-example/network)

[![GitHub stars](https://img.shields.io/github/stars/benoutram/terraform-aws-vpc-example.svg)](https://github.com/benoutram/terraform-aws-vpc-example/stargazers)

[![GitHub license](https://img.shields.io/github/license/benoutram/terraform-aws-vpc-example.svg)](https://github.com/benoutram/terraform-aws-vpc-example/blob/master/LICENSE)

[![Twitter Follow](https://img.shields.io/twitter/follow/benoutram.svg?style=social&label=Follow)](https://twitter.com/intent/follow?screen_name=benoutram)

## What is this repository for? ##

This is an example Terraform project which deploys a web application using AWS infrastructure that is:

* Isolated in a VPC
* Load balanced
* Auto scaled
* Secured by SSL
* DNS routed with Route53
* Restricted to traffic from a list of allowed IP addresses
* Accessible by SSH

The [Spring Boot S3 Example](https://github.com/benoutram/springboot-s3-example) web application is deployed to web server instances to visually demonstrate the successful deployment of the infrastructure. A build of the application resides in Amazon S3 storage which is fetched during provisioning of web server instances and set up to run as a service.

The [Spring Boot S3 Example](https://github.com/benoutram/springboot-s3-example) web application has a MySQL database dependency to demonstrate database connectivity with RDS.

## How do I get set up? ##

### Dependencies ###

This project assumes that you are already familiar with AWS and Terraform.

There are several dependencies that are needed before the Terraform project can be run. Make sure that you have:

  * The [Terraform](https://www.terraform.io) binary installed and available on the PATH.
  * The Access Key ID and Secret Access Key of an AWS IAM user that has programmatic access enabled.
  * A Hosted Zone in AWS Route 53 for the desired domain name of the application.
  * The certificate ARN of an AWS Certificate Manager SSL certificate for the domain name.
  * An OpenSSH key pair that will be used to control login access to EC2 instances.

### Grant User permissions required for Terraform actions ###

Terraform is unable to check which IAM permissions are missing during the *plan* phase and will fail during the *apply* phase if the user doesn't have the necessary permissions.

Rather than configuring a user with unrestricted access, this project has been tested with a user that has the AWS `PowerUserAccess` policy.

1. Create an IAM group which will be used for Terraform users e.g. `TerraformUsers`.
2. Attach the AWS managed policy `PowerUserAccess` to the group.
3. Add your IAM user to the new group.

### Configure the project properties ###

Create a file `user.tfvars` in the root of the project with the following template:

```javascript
access_key = ""
secret_key = ""
database_password = ""
public_key_path = ""
certificate_arn = ""
route53_hosted_zone_name = ""
allowed_cidr_blocks = []
```

Populate the properties as follows:

1. `access_key` and `secret_key` are the Access Key ID and Secret Access Key of an AWS IAM user that has programmatic access enabled.
2. `database_password` is a random password that will be the MySQL password for the Terraform user account used by the web application.
3. `public_key_path` is the local path to the OpenSSH public key file of a key pair that should have access to EC2 web server instances, e.g. /home/*you*/.ssh/id_rsa_terraform.pub.
4. `certificate_arn` is the ARN of an AWS Certificate Manager SSL certificate for the domain name that you want to use, e.g. arn:aws:acm:eu-west-1:123456789012:certificate/12345678-1234-1234-1234-123456789012.
5. `route53_hosted_zone_name` is the domain name of the Hosted Zone managed in Route 53 e.g. example.com. A 'terraform' hostname will be created within this domain.
6. `allowed_cidr_blocks` is a list of allowed CIDR blocks that should have SSL access to the application load balancer and SSH access to the EC2 web server instances, e.g. ["0.0.0.0/0"].

Other project properties such as the AWS region and EC2 instance type can be found defined in file `terraform.tfvars`. If you change the region then you will also need to make sure an AMI is defined for it.

## Deployment ##

### Plan the deployment ###

`terraform plan -var-file="user.tfvars"`

### Apply the deployment ###

`terraform apply -var-file="user.tfvars"`

During provisioning of the web server instances, a build of the [Spring Boot S3 Example](https://github.com/benoutram/springboot-s3-example) project will be copied from the S3 bucket defined in the project properties.

If the deployment is successful you should now be able to see the infrastructure created in the AWS web console. After a delay while the web instances are initialised you should be able to launch the sample web application at https://terraform.[your-domain.com].

![image](https://github.com/benoutram/springboot-s3-example/blob/master/docs/screenshots/login.png?raw=true "Login")

There is one sample user that can be used to login:

| Username       | Password |
| -------------- | ---------|
| john@smith.com | password |

![image](https://github.com/benoutram/springboot-s3-example/blob/master/docs/screenshots/welcome.png?raw=true "Welcome")

You can also SSH to any of the public IP addresses of the EC2 web server instances.

```
ssh ec2-user@[ipaddress]
```

### Destroy the deployment ###

`terraform destroy -var-file="user.tfvars"`
