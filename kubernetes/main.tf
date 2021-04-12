
provider "aws" {
  region = "eu-west-1"
  #---
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  //load_config_file       = true
  version     = "~> 1.11"
  config_path = "~/.kube/config"
}

data "aws_availability_zones" "available" {
}

locals {
  cluster_name = "my-cluster"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.47.0"

  name                 = "k8s-vpc"
  cidr                 = "172.16.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  public_subnets       = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}


module "eks" {
  source = "terraform-aws-modules/eks/aws"
  //version = "12.2.0"

  cluster_name    = "${local.cluster_name}"
  cluster_version = "1.17"
  subnets         = module.vpc.private_subnets

  vpc_id = module.vpc.vpc_id

  node_groups = {
    first = {
      desired_capacity = 1
      max_capacity     = 5
      min_capacity     = 1

      instance_type = "t2.micro"
    }
    gpu = {
      desired_capacity = 1
      max_capacity     = 5
      min_capacity     = 1

      instance_type = "t2.micro"
    }

  }
  wait_for_cluster_cmd        = "until curl -k -s $ENDPOINT/healthz >/dev/null; do sleep 4; done"
  write_kubeconfig            = true
  config_output_path          = "./"
  workers_additional_policies = [aws_iam_policy.worker_policy.arn]
}

resource "aws_iam_policy" "worker_policy" {
  name        = "worker-policy"
  description = "Worker policy for the ALB Ingress"

  policy = file("iam-policy.json")
}



resource "kubernetes_namespace" "timestamps" {
  metadata {
    name = "timestamps"
  }
}


resource "kubernetes_secret" "stamp_secret" {
  metadata {
    name      = "stamp-secret"
    namespace = kubernetes_namespace.timestamps.metadata.0.name
  }
  data = {
    "APP-PASSWORD" = "a2VubnkxMjM0"
    //"DB_USER" = "admin"
    "DB_PWD" = "c3RhbXBzMTIz"

    //db_root_password = "c3RhbXBzMTIz"
  }
  type = "Opaque"
}


resource "kubernetes_service" "stamp_webapp" {
  metadata {
    name      = "stamp-webapp"
    namespace = kubernetes_namespace.timestamps.metadata.0.name
  }
  spec {
    selector = {
      app = "${kubernetes_deployment.timestamps_deployment.spec.0.template.0.metadata.0.labels.app}"
    }
    type = "LoadBalancer"
    port {
      port        = 80
      target_port = 5000
      node_port   = 30000
    }
  }
}



resource "kubernetes_deployment" "timestamps_deployment" {
  metadata {
    name      = "timestamps-deploy"
    namespace = kubernetes_namespace.timestamps.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "stamp-webapp"
      }
    }
    template {
      metadata {
        labels = {
          app = "stamp-webapp"
        }
      }
      spec {

        /*init_container {
                name              = "init-db"
                image             = "busybox:1.31"
                //command = ["sh", "-c", "echo -e Checking for the availability of MySQL Server deployment; while ! nc -z mysql 3306; do sleep 1; printf "-"; done; echo -e  >> MySQL DB Server has started;"]
                 command = ['sh', '-c', 'echo -e "Checking for the availability of MySQL Server deployment"; while ! nc -z mysql 3306; do sleep 1; printf "-"; done; echo -e "  >> MySQL DB Server has started";']      
                image_pull_policy = "IfNotPresent"
                }*/

        container {
          image = "kagboola/bola_timestamps:latest"

          name = "stamp-webapp"
          //imagePullPolicy = Always
          port {
            container_port = 5000
          }
          env {
            name = "MYSQL_DB_PWD"
            value_from {
              secret_key_ref {
                key  = "DB_PWD"
                name = kubernetes_secret.stamp_secret.metadata.0.name
              }
            }
          }
         
          env {
            name  = "MYSQL_DB_USER"
            value = "admin"
          }
          env {
            name  = "MYSQL_SERVICE_HOST"
            value = "stamps-app.cugmzubqhre7.eu-west-1.rds.amazonaws.com"
          }

          env {
            name  = "MYSQL_DB_NAME"
            value = "stamps_app"
          }

        }



        volume {
          name = "${kubernetes_secret.stamp_secret.metadata.0.name}"
          secret {
            secret_name = "${kubernetes_secret.stamp_secret.metadata.0.name}"
          }
        }
      }
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler" "stamp_hpa" {
  metadata {
    name = "test"
    namespace = kubernetes_namespace.timestamps.metadata.0.name
  }

  spec {
    min_replicas = 1
    max_replicas = 5

    scale_target_ref {
      kind = "Deployment"
      name = "MyApp"
    }

    metric {
      type = "External"
      external {
        metric {
          name = "latency"
          selector {
            match_labels = {
              lb_name = "stamp-webapp"
            }
          }
        }
        target {
          type  = "Value"
          value = "5"
        }
      }
    }
  }
}



