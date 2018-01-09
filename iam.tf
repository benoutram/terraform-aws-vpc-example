# Create a profile for the S3 access role that will passed to the EC2 instances when they start.
resource "aws_iam_instance_profile" "example_profile" {
  name = "terraform_instance_profile"
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
      "Resource": ["arn:aws:s3:::${var.s3_bucket_name}"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": ["arn:aws:s3:::${var.s3_bucket_name}/*"]
    }
  ]
}
EOF
}
