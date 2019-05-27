terraform {
	required_version = ">= 0.12"
}

provider "aws" {
	region  = "us-east-2"
	#profile = "work"
}

locals {
	all_cidr      = "0.0.0.0/0"
	prefix        = "playground"
	region        = "us-east-2"
	volume_size   = "30"
	instance_type = "t3.large"
	nodegroup     = format("%s-Nodegroup-%s", local.prefix, local.instance_type)
	subnets       = 3
	min_instances = 3
	public_key_filename  = "${path.root}/keys/playground.pub"
	private_key_filename = "${path.root}/keys/playground.pem"
	cluster_tag = { "kubernetes.io/cluster/${local.prefix}" = "" }
  enable_autoscaler = {"k8s.io/cluster-autoscaler/enabled" = "" }
}

########################
## AWS Keypair
########################
resource "tls_private_key" "generated" {
	algorithm = "RSA"
}

resource "aws_key_pair" "generated" {
	key_name   = "playground"
	public_key = tls_private_key.generated.public_key_openssh

	lifecycle {
		ignore_changes = ["key_name"]
	}
}

resource "local_file" "public_key_openssh" {
	content  = tls_private_key.generated.public_key_openssh
	filename = local.public_key_filename
}

resource "local_file" "private_key_pem" {
	content  = tls_private_key.generated.private_key_pem
	filename = local.private_key_filename
}

resource "null_resource" "chmod" {
	depends_on = [ local_file.private_key_pem ]

	triggers = {
		key = "tls_private_key.generated.private_key_pem"
	}

	provisioner "local-exec" {
		command = "chmod 600 ${local.private_key_filename}"
	}
}
########################
## AWS Network
########################
resource "aws_vpc" "playground" {
	cidr_block           = "10.195.0.0/16"
	enable_dns_hostnames = true
	enable_dns_support   = true

	tags = merge({ "Name" = local.prefix}, {format("kubernetes.io/cluster/%s", local.prefix) = "shared"})
}

resource "aws_subnet" "public_subnet" {
	count                   = 3
	map_public_ip_on_launch = true

	availability_zone = data.aws_availability_zones.available.names[count.index]

	cidr_block = cidrsubnet(aws_vpc.playground.cidr_block, 8, count.index + 11)
	vpc_id     = aws_vpc.playground.id

	tags = merge({"Name" = format("%s-public-%d", local.prefix, count.index)}, local.cluster_tag)
}

resource "aws_route_table" "public" {
	vpc_id = aws_vpc.playground.id
}

resource "aws_internet_gateway" "public_gateway" {
	vpc_id = aws_vpc.playground.id
}

resource "aws_route_table_association" "public" {
	count          = length(aws_subnet.public_subnet)
	route_table_id = aws_route_table.public.id
	subnet_id      = aws_subnet.public_subnet[count.index].id
}

resource "aws_route" "internet_gateway" {
	route_table_id         = aws_route_table.public.id
	gateway_id             = aws_internet_gateway.public_gateway.id
	destination_cidr_block = local.all_cidr
}

########################
## EKS Control Plane
########################
resource "aws_iam_role" "eks-control" {
	name = format("%s-EKSControlPlane", local.prefix)

	assume_role_policy = jsonencode({
		  "Version": "2012-10-17",
		  "Statement": [
		    {
		      "Action": "sts:AssumeRole",
		      "Principal": {
		        "Service": "eks.amazonaws.com"
		      },
		      "Effect": "Allow",
		      "Sid": ""
		    }
		  ]
		})
}

resource "aws_iam_role_policy_attachment" "allow-cluster" {
	role       = aws_iam_role.eks-control.name
	policy_arn = data.aws_iam_policy.AmazonEKSClusterPolicy.arn
}

resource "aws_iam_role_policy_attachment" "allow-service" {
	role       = aws_iam_role.eks-control.name
	policy_arn = data.aws_iam_policy.AmazonEKSServicePolicy.arn
}

resource "aws_security_group" "eks-control" {
	name   = format("%s-EKSPlane", local.prefix)
	vpc_id = aws_vpc.playground.id
	ingress {
		from_port   = 0
		protocol    = "-1"
		to_port     = 0
		cidr_blocks = [ local.all_cidr ]
	}
	egress {
		from_port   = 0
		protocol    = "-1"
		to_port     = 0
		cidr_blocks = [ local.all_cidr ]
	}
}

resource "aws_eks_cluster" "playground" {
	name     = local.prefix
	role_arn = aws_iam_role.eks-control.arn
	version  = "1.12"

	vpc_config {
		subnet_ids             = aws_subnet.public_subnet.*.id
		security_group_ids     = [ aws_security_group.eks-control.id ]
		endpoint_public_access = true
	}
}

########################
## EKS Worker Nodes
########################
resource "aws_iam_role" "eks-node" {
	name               = format("%s-EKSNode", local.prefix)
	assume_role_policy = jsonencode({
	  "Version": "2012-10-17",
	  "Statement": [
	    {
	      "Action": "sts:AssumeRole",
	      "Principal": {
	        "Service": "ec2.amazonaws.com"
	      },
	      "Effect": "Allow",
	      "Sid": ""
	    }
	  ]
	})
}

resource "aws_iam_role_policy_attachment" "allow-worker" {
	role = aws_iam_role.eks-node.name
	policy_arn = data.aws_iam_policy.AmazonEKSWorkerNodePolicy.arn
}

resource "aws_iam_role_policy_attachment" "allow-ecr" {
	role       = aws_iam_role.eks-node.name
	policy_arn = data.aws_iam_policy.AmazonEC2ContainerRegistryReadOnly.arn
}

resource "aws_iam_role_policy_attachment" "allow-cni" {
	role       = aws_iam_role.eks-node.name
	policy_arn = data.aws_iam_policy.AmazonEKS_CNI_Policy.arn
}

resource "aws_iam_instance_profile" "eks-node" {
	name = format("%s-EKSNode", local.prefix)
	role = aws_iam_role.eks-node.name
}

resource "aws_security_group" "eks-node" {
	name   = format("%s-EKSNode", local.prefix)
	vpc_id = aws_vpc.playground.id
	ingress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks = [ local.all_cidr ]
	}
	egress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks = [ local.all_cidr ]
	}
}

data "template_file" "node-bootstrap" {
	template = file("bootstrap.sh")
	vars     = {
		BootstrapArguments = ""
		ClusterName        = aws_eks_cluster.playground.name
	}
}

resource "aws_launch_template" "basic" {
	disable_api_termination              = false
	instance_initiated_shutdown_behavior = "terminate"
	instance_type                        = local.instance_type
	key_name                             = aws_key_pair.generated.key_name
	vpc_security_group_ids               = [ aws_security_group.eks-node.id ]
	image_id                             = "ami-04ea7cb66af82ae4a"

	block_device_mappings {
		device_name = "/dev/xvda"

		ebs {
			volume_size = local.volume_size
		}
	}

	iam_instance_profile {
		name = aws_iam_instance_profile.eks-node.name
	}

	monitoring {
		enabled = true
	}

	tag_specifications {
		resource_type = "instance"

		tags = merge( {"Name" = local.nodegroup }, local.enable_autoscaler, local.cluster_tag)
	}

	user_data = base64encode(data.template_file.node-bootstrap.rendered)

	depends_on = [
		aws_eks_cluster.playground
	]
}

resource "aws_autoscaling_group" "t3-large" {
	availability_zones = aws_subnet.public_subnet.*.availability_zone_id
	desired_capacity   = 3
	max_size           = 3
	min_size           = 0

	vpc_zone_identifier  = aws_subnet.public_subnet.*.id
	termination_policies = [ "OldestInstance", "AllocationStrategy", "OldestLaunchTemplate" ]

	launch_template {
		id      = aws_launch_template.basic.id
		version = "$Latest"
	}
}

data "template_file" "aws-auth" {
	template = file("aws-auth.yaml.tpl")
	vars     = {
		role_arn = aws_iam_role.eks-node.arn
	}
}

resource "local_file" "aws_auth" {
	content  = data.template_file.aws-auth.rendered
	filename = "./aws-auth.yaml"
}

output "to_run" {
	value = "aws eks update-kubeconfig --name ${local.prefix} && kubectl apply -f aws-auth.yaml"
}
