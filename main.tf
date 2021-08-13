# main.tf

resource "kubernetes_namespace" "this" {
  count = var.namespace == "" ? 1 : 0
  metadata {
    name = var.namespace_name
  }
}

resource "helm_release" "grafana" {
  count = var.grafana_enabled ? 1 : 0

  name          = local.grafana_name
  repository    = local.grafana_repository
  chart         = local.grafana_chart
  version       = var.grafana_chart_version
  namespace     = local.namespace
  recreate_pods = true
  timeout       = 1200

  dynamic "set" {
    for_each = merge(local.grafana_conf)

    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "prometheus" {
  count = var.prometheus_enabled ? 1 : 0

  name          = local.prometheus_name
  repository    = local.prometheus_repository
  chart         = local.prometheus_chart
  version       = var.prometheus_chart_version
  namespace     = local.namespace
  recreate_pods = true
  timeout       = 1200

  dynamic "set" {
    for_each = merge(local.prometheus_conf)

    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "thanos" {
  count = var.thanos_enabled ? 1 : 0

  name          = local.thanos_name
  repository    = local.thanos_repository
  chart         = local.thanos_chart
  version       = var.thanos_chart_version
  namespace     = local.namespace
  recreate_pods = true
  timeout       = 1200

  dynamic "set" {
    for_each = merge(local.thanos_conf)

    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "random_password" "grafana_password" {
  length           = 16
  special          = true
  override_special = "!#%&*()-_=+[]{}<>:?"
}

resource "aws_ssm_parameter" "grafana_password" {
  name  = "/${var.cluster_name}/grafana/password"
  type  = "SecureString"
  value = local.grafana_password
}

resource "random_password" "thanos_password" {
  length           = 16
  special          = true
  override_special = "!#%&*()-_=+[]{}<>:?"
}

module "iam_assumable_role_admin" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "~> v3.6.0"
  create_role                   = true
  role_name                     = "${data.aws_eks_cluster.this.id}_${local.thanos_name}"
  provider_url                  = replace(data.aws_eks_cluster.this.identity.0.oidc.0.issuer, "https://", "")
  role_policy_arns              = [aws_iam_policy.thanos.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:${local.namespace}:${local.thanos_name}"]
  tags                          = var.tags
}

resource "aws_iam_policy" "thanos" {
  name_prefix = "${data.aws_eks_cluster.this.id}-thanos-"
  description = "EKS thanos-s3 policy for cluster ${data.aws_eks_cluster.this.id}"
  policy = jsonencode(
    {
      Version = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "s3:ListBucket",
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:PutObject",
            "s3:CreateBucket",
            "s3:DeleteBucket"
          ],
          Resource = local.policy_resource
        }
      ]
    }
  )
}

resource "aws_ssm_parameter" "thanos_password" {
  count = local.storage
  name  = "/${var.cluster_name}/thanos/password"
  type  = "SecureString"
  value = local.thanos_password
}

resource "aws_s3_bucket" "thanos" {
  count  = 1 - local.storage
  bucket = "${var.cluster_name}-thanos"
  acl    = "private"

  tags = var.tags
}

resource "kubernetes_secret" "thanos_objstore" {
  count      = local.storage
  depends_on = [kubernetes_namespace.this]
  metadata {
    name      = "thanos-objstore-config"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name" : "thanos-objstore-config"
      "app.kubernetes.io/part-of" : "thanos"
    }
  }
  data = {
    "objstore.yml" = <<EOT
type: s3
config:
  bucket: thanos
  endpoint: thanos-minio.monitoring.svc.cluster.local:9000
  access_key: thanosStorage
  secret_key: ${local.thanos_password}
  insecure: true
  EOT
  }
}

resource "kubernetes_secret" "s3_objstore" {
  count      = 1 - local.storage
  depends_on = [kubernetes_namespace.this]
  metadata {
    name      = "thanos-objstore-config"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name" : "thanos-objstore-config"
      "app.kubernetes.io/part-of" : "thanos"
    }
  }
  data = {
    "objstore.yml" = <<EOT
type: s3
config:
  bucket: ${var.cluster_name}-thanos
  endpoint: s3.${data.aws_region.current.name}.amazonaws.com
  insecure: false
  EOT
  }
}
