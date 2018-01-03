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

# Write a configuration file with our Spring Boot run arguments
sudo cat << EOF > /opt/springboot-s3-example/springboot-s3-example.conf
RUN_ARGS="--spring.datasource.url=jdbc:mysql://${database_endpoint}/terraform_test_db?useSSL=false --spring.datasource.password=${database_password}"
EOF
sudo chmod 400 /opt/springboot-s3-example/springboot-s3-example.conf
sudo chown springboot:springboot /opt/springboot-s3-example/springboot-s3-example.conf

# Write a Nginx site configuration file to redirect port 80 to 8080
sudo cat << EOF > /etc/nginx/conf.d/springboot-s3-example-nginx.conf
server {
    listen 80 default_server;
    server_name terraform.benoutram.co.uk;

    if (\$http_x_forwarded_proto != 'https') {
      return 301 https://\$host\$request_uri;
    }

    location / {
        proxy_set_header    X-Real-IP \$remote_addr;
        proxy_set_header    Host \$http_host;
        proxy_set_header    X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto \$scheme;
        proxy_pass          http://127.0.0.1:8080;
    }
}
EOF

# Rewrite the default Nginx configuration file to disable the default site
sudo cat << EOF > /etc/nginx/nginx.conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /var/run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;
    
    index   index.html index.htm;
}
EOF

# Set owner read and execute mode on the Spring Boot application for the new user
sudo chown springboot:springboot /opt/springboot-s3-example/springboot-s3-example.jar
sudo chmod 500 /opt/springboot-s3-example/springboot-s3-example.jar

# Install the Spring Boot application as an init.d service by creating a symlink
sudo ln -s /opt/springboot-s3-example/springboot-s3-example.jar /etc/init.d/springboot-s3-example

# Automatically start services
sudo chkconfig nginx on
sudo chkconfig springboot-s3-example on

# Start the Nginx and Spring Boot services
sudo service nginx start
sudo service springboot-s3-example start