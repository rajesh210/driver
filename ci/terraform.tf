provider "aws" {
	region = "us-west-2"
}

provider "template" {
}

variable "ssh_key_pub" {}
variable "project_name" {}
variable "ci_pipeline_id" {}

variable "flatcar_channel" {
	type        = string
	default     = "stable"
	description = "Flatcar channel to deploy on instances"
}

data "aws_ami" "ubuntu16_04" {
	most_recent = true

	owners = ["099720109477"]

	filter {
		name = "name"
		values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
	}
}

resource "random_id" "server" {
  byte_length = 8
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh-${random_id.server.dec}"
  description = "Allow ssh connections on port 22"

  ingress {
    from_port   = 22
    to_port     = 22
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

data "template_cloudinit_config" "ubuntu16_04" {
	gzip          = true
	base64_encode = true

	part {
		content_type = "text/cloud-config"
		content = <<EOF
#cloud-config

apt:
  preserve_sources_list: true
  sources:
    docker.list:
      source: "deb [arch=amd64] https://download.docker.com/linux/ubuntu $RELEASE test"
      keyid: 0EBFCD88

packages:
  - docker-ce

users:
  - name: nvidia
    lock_passwd: True
    sudo:  ALL=(ALL) NOPASSWD:ALL
    groups:
      - docker
    ssh_authorized_keys: ${file(var.ssh_key_pub)}
EOF
	}
}

resource "aws_instance" "ubuntu16_04" {
	ami           = data.aws_ami.ubuntu16_04.id
	instance_type = "c4.4xlarge"

	tags = {
		Name = "${var.project_name}-${var.ci_pipeline_id}-ubuntu16_04"
		product = "cloud-native"
		project = var.project_name
		environment = "cicd"
	}

	root_block_device {
		volume_size = 40
	}

	security_groups = ["default", aws_security_group.allow_ssh.name]

	connection {
		user = "nvidia"
		host = self.public_ip
		agent = true
	}

	provisioner "remote-exec" {
		inline = [
			"cloud-init status --wait",
			"sudo modprobe ipmi_msghandler",
		]
	}

	user_data = data.template_cloudinit_config.ubuntu16_04.rendered
}

output "public_ip_ubuntu16_04" {
	value = aws_instance.ubuntu16_04.public_ip
}

# Get the latest Flatcar Pro AMI available for the given channel
data "aws_ami" "flatcar_pro_latest" {
	most_recent = true
	owners      = ["aws-marketplace"]

	filter {
		name   = "architecture"
		values = ["x86_64"]
	}

	filter {
		name   = "virtualization-type"
		values = ["hvm"]
	}

	filter {
		name   = "name"
		values = ["Flatcar-pro-${var.flatcar_channel}-*"]
	}
}

# Launch the latest CoreOS instance
data "aws_ami" "coreos" {
	most_recent = true

	owners = ["679593333241"]

	filter {
		name = "name"
		values = ["CoreOS-stable-*"]
	}
}
