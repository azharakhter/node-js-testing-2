# Specify the required Terraform providers
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16" # AWS provider version
    }
  }

  required_version = ">= 1.2.0" # Minimum Terraform version
}

# Configure the AWS provider
provider "aws" {
  region = "us-west-2" # Free-tier eligible region
}


data "aws_caller_identity" "current" {}


# Step 1: Create an S3 bucket for storing Terraform state or other objects
resource "aws_s3_bucket" "my_s3_bucket" {
  bucket = "my-app-storage-bucket-azhar-001" # Replace with a unique S3 bucket name

  versioning {
    enabled = true # Enable versioning to retain state file history
  }

  lifecycle_rule {
    id      = "expire-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 30 # Keep older versions for 30 days
    }
  }

  tags = {
    Name        = "my-s3-bucket"
    Environment = "dev"
  }
}

# Step 2: Attach an S3 bucket policy to allow the IAM role access
resource "aws_s3_bucket_policy" "my_s3_bucket_policy" {
  bucket = aws_s3_bucket.my_s3_bucket.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecs_task_execution_role"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${aws_s3_bucket.my_s3_bucket.bucket}",
        "arn:aws:s3:::${aws_s3_bucket.my_s3_bucket.bucket}/*"
      ]
    }
  ]
}
POLICY
}


# Step 3: Create a DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-lock-table"
  billing_mode = "PAY_PER_REQUEST"  # Use the on-demand pricing model
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "terraform-lock-table"
    Environment = "dev"
  }
}

# Step 4: Create an ECR (Elastic Container Registry) repository
resource "aws_ecr_repository" "my_node_app" {
  name                 = "my-node-app"
  image_tag_mutability = "MUTABLE"
  # ECR stores your Docker images, and it will be used to pull the image in ECS
}

# Step 5: Create an ECS (Elastic Container Service) cluster
resource "aws_ecs_cluster" "my_cluster" {
  name = "my-cluster"
  # This defines the ECS cluster where your tasks and services will run
}

# Step 6: Define the ECS task execution IAM role with S3 and DynamoDB access
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"

  # The ECS service needs permissions to pull Docker images and run tasks
  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        }
      }
    ]
  }
  EOF
}

# Attach the ECS task execution policy to the role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  # This provides permissions needed by ECS to pull from ECR and execute containers
}

# Attach S3 full access to the role
resource "aws_iam_role_policy_attachment" "s3_full_access_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  # This provides full access to all S3 resources
}

# Attach DynamoDB full access to the role
resource "aws_iam_role_policy_attachment" "dynamodb_full_access_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  # This provides full access to all DynamoDB resources
}

# Step 7: Define the ECS task definition
resource "aws_ecs_task_definition" "my_task" {
  family                   = "my-task"
  network_mode             = "awsvpc"  # Uses AWS VPC for networking
  requires_compatibilities = ["FARGATE"] # We are using Fargate (serverless)
  cpu                      = 256       # Minimal CPU (free-tier eligible)
  memory                   = 512       # Minimal memory (free-tier eligible)
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  # This defines the container that will run in the ECS task
  container_definitions = <<DEFINITION
  [
    {
      "name": "my-container",
      "image": "${aws_ecr_repository.my_node_app.repository_url}:latest",
      "cpu": 256,
      "memory": 512,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000
        }
      ]
    }
  ]
  DEFINITION
}

# Step 8: Create a security group for ECS service
resource "aws_security_group" "ecs_sg" {
  name        = "ecs_sg"
  description = "Allow HTTP traffic on port 3000"
  vpc_id      = aws_vpc.main.id  # Link to the VPC created or existing VPC

  ingress {
    from_port   = 3000   # Allows traffic to port 3000 (Node.js app)
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow traffic from all IPs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound traffic
  }
}

# Step 9: Create a VPC and Subnet for ECS service
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "ecs_subnet" {
  vpc_id                  = aws_vpc.main.id  # Link the subnet to the VPC
  cidr_block              = "10.0.1.0/24"    # Define the IP range for this subnet
  availability_zone       = "us-west-2a"     # Choose the availability zone
  map_public_ip_on_launch = true             # Automatically assign public IP addresses to instances
}

# Step 10: Create the ECS service to run the task
resource "aws_ecs_service" "my_service" {
  name            = "my-service"
  cluster         = aws_ecs_cluster.my_cluster.id # Link to the ECS cluster
  task_definition = aws_ecs_task_definition.my_task.arn # Link to the task definition
  desired_count   = 1   # Number of instances of the container to run
  launch_type     = "FARGATE" # Use Fargate to avoid managing EC2 instances

  # Network configuration for the Fargate task
  network_configuration {
    subnets         = [aws_subnet.ecs_subnet.id]  # Use the subnet created
    security_groups = [aws_security_group.ecs_sg.id] # Use the security group created
  }
}
