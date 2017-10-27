#!/bin/bash

###
## Provision the Spring Boot application
## Adapted from the following blog post:
## http://zoltanaltfatter.com/2016/12/17/spring-boot-application-on-ec2/
###

sudo yum update -y

# Install Nginx
sudo yum install nginx -y

# Install Java
sudo yum install java-1.8.0-openjdk-devel -y
sudo yum remove java-1.7.0-openjdk -y

# Create a new user to run the Spring Boot application as a service and disable the login shell
sudo useradd springboot
sudo chsh -s /sbin/nologin springboot

# Copy the Spring Boot application from S3
sudo mkdir /opt/springboot-s3-example
sudo aws s3 cp s3://springboot-s3-example/ /opt/springboot-s3-example/ --region=eu-west-1 --recursive --exclude "*" --include "springboot-s3-example*.jar"
sudo mv /opt/springboot-s3-example/springboot-s3-example*.jar /opt/springboot-s3-example/springboot-s3-example.jar

# Set owner read and execute mode on the Spring Boot application for the new user
sudo chown springboot:springboot /opt/springboot-s3-example/springboot-s3-example.jar
sudo chmod 500 /opt/springboot-s3-example/springboot-s3-example.jar

# Install the Spring Boot application as an init.d service by creating a symlink
sudo ln -s /opt/springboot-s3-example/springboot-s3-example.jar /etc/init.d/springboot-s3-example

# Automatically start services
sudo chkconfig nginx on
sudo chkconfig springboot-s3-example on
