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

resource "aws_ecs_cluster" "group1-tf-cp2-cluster" {
  name = "group1-tf-cp2-cluster"
}

resource "aws_ecr_repository" "group1-tf-cp2-ecr-repo" {
  name = "group1-tf-cp2-ecr-repo"
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

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "group1TaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_ecs_task_definition" "group1-tf-cp2-task" {
  family                   = "group1-tf-cp2-task"
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
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

resource "aws_default_vpc" "default_vpc" {
}

resource "aws_security_group" "load_balancer_security_group" {
  vpc_id        = "${aws_default_vpc.default_vpc.id}"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-west-2a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-west-2b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "us-west-2c"
}

resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_alb" "application_load_balancer" {
  name               = "group1-tf-cp2-alb"
  internal           = false
  load_balancer_type = "application"
  subnets = [
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}"
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "group1-tf-cp2-tg"
  port        = "80"
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}"
}

resource "aws_ecs_service" "group1-tf-cp2_service" {
  name            = "group1-tf-cp2-service"
  cluster         = "${aws_ecs_cluster.group1-tf-cp2-cluster.id}"
  task_definition = "${aws_ecs_task_definition.group1-tf-cp2-task.arn}"
  launch_type     = "FARGATE"
  desired_count   = 3
  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
    container_name   = "${aws_ecs_task_definition.group1-tf-cp2-task.family}"
    container_port   = 3000
  }

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true
    security_groups  = ["${aws_security_group.service_security_group.id}"]
  }
}

resource "aws_s3_bucket" "group1-tf-cp2-bucket-create" {
  bucket = "group1-tf-cp2-bucket"
}

resource "aws_s3_bucket_versioning" "group1-tf-cp2-bucket-verison" {
  bucket = "${aws_s3_bucket.group1-tf-cp2-bucket-create.id}"
  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


/*
resource "aws_lb_target_group_attachment" "target_group_attachment" {
  target_group_arn = "${aws_lb_target_group.target_group.arn}"
  target_id        = "${aws_ecs_task_definition.group1-tf-cp2-task.execution_role_arn}"
  port             = 3000
}
*/