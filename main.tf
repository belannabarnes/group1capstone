terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.1.0"
}

provider "aws" {
  region     = "us-west-2"
}

/* ------- S3 Bucket ------ */
resource "aws_s3_bucket" "group1-tf-cp2-bucket-create" {
  bucket = "group1-tf-cp2-bucket"
}

resource "aws_s3_bucket_versioning" "group1-tf-cp2-bucket-verison" {
  bucket = aws_s3_bucket.group1-tf-cp2-bucket-create.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "group1-tf-cp2-bucket-add" {
  for_each = fileset("./jsondata/", "**")
  bucket   = aws_s3_bucket.group1-tf-cp2-bucket-create.id
  key      = each.key
  source   = "./jsondata/${each.value}"
  etag     = filemd5("./jsondata/${each.value}")
} 


/* ------- ECR Repo ------ */
resource "aws_ecr_repository" "group1-tf-cp2-ecr-repo" {
  name = "group1-tf-cp2-ecr-repo"
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "group1-cp-artifact-bucket"
}

# Providing a reference to our default VPC
resource "aws_default_vpc" "default_vpc" {
}

# Providing a reference to our default subnets
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-west-2a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-west-2b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "us-west-2c"
}


resource "aws_ecs_cluster" "group1-tf-cp2-cluster" {
  name = "group1-tf-cp2-cluster" # Naming the cluster
}

resource "aws_ecs_task_definition" "group1-tf-cp2-task" {
  family                   = "group1-tf-cp2-task" # Naming our first task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "group1-tf-cp2-task",
      "image": "${aws_ecr_repository.group1-tf-cp2-ecr-repo.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
}

# data "aws_iam_role" "ecsTaskExecutionRole" {
#   name = "ecsTaskExecutionRole"
# }

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "group1TaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_alb" "application_load_balancer" {
  name               = "group1-tf-cp2-alb" # Naming our load balancer
  load_balancer_type = "application"
  subnets = [ # Referencing the default subnets
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
  # Referencing the security group
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "group1-tf-cp2-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_default_vpc.default_vpc.id # Referencing the default VPC
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_alb.application_load_balancer.arn # Referencing our load balancer
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn # Referencing our target group
  }
}

resource "aws_ecs_service" "group1-tf-cp2_service" {
  name            = "arev-tf-cp2-service"                        # Naming our first service
  cluster         = aws_ecs_cluster.group1-tf-cp2-cluster.id       # Referencing our created Cluster
  task_definition = aws_ecs_task_definition.group1-tf-cp2-task.arn # Referencing the task our service will spin up
  launch_type     = "FARGATE"
  desired_count   = 3 # Setting the number of containers to 3

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn # Referencing our target group
    container_name   = aws_ecs_task_definition.group1-tf-cp2-task.family
    container_port   = 3000 # Specifying the container port
  }

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true                                                # Providing our containers with public IPs
    security_groups  = ["${aws_security_group.service_security_group.id}"] # Setting the security group
  }
}


resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
