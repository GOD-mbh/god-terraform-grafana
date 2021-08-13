# locals.tf

locals {

  storage         = var.thanos_storage == "s3" ? 0 : 1
  namespace       = var.namespace == "" ? var.namespace_name : var.namespace
  policy_resource = local.storage == 0 ? "[\"arn:aws:s3:::${aws_s3_bucket.thanos[0].id}/*\", \"arn:aws:s3:::${aws_s3_bucket.thanos[0].id}\"]" : "[]"

  #Grafana
  grafana_name       = "grafana"
  grafana_repository = "https://grafana.github.io/helm-charts"
  grafana_chart      = "grafana"
  grafana_conf       = merge(local.grafana_conf_defaults, var.grafana_conf)
  grafana_password   = var.grafana_password == "" ? random_password.grafana_password.result : var.grafana_password
  grafana_values = yamlencode(
    {
      "datasources.yaml" = {
        "apiVersion" = "1"
        "datasources" = [{
          "name"      = "Prometheus"
          "type"      = "prometheus"
          "url"       = "http://thanos-query:9090"
          "access"    = "proxy"
          "isDefault" = true
        }]
      }
      # "dashboards" = {
      #     "default" = {
      #       "prometheus-stats" = {
      #         "gnetId"     = "2"
      #         "revision"   = "2"
      #         "datasource" = "Prometheus"
      #       }
      #     }
      #   }
  })

  grafana_conf_defaults = {
    "ingress.enabled"           = true
    "ingress.ingressClassName"  = "nginx"
    "ingress.annotations"       = "{ kubernetes.io/tls-acme: 'true' }"
    "ingress.hosts[0]"          = "grafana.${var.domains[0]}"
    "ingress.tls[0].secretName" = "grafana-tls"
    "ingress.tls[0].hosts[0]"   = "grafana.${var.domains[0]}"

    "persistence.enabled" = true
    "persistence.size"    = "10Gi"

    "adminPassword"          = local.grafana_password
    "env.GF_SERVER_ROOT_URL" = "https://grafana.${var.domains[0]}"
    "namespace"              = local.namespace
  }

  #Prometheus
  prometheus_name       = "kube-prometheus"
  prometheus_repository = "https://charts.bitnami.com/bitnami"
  prometheus_chart      = "kube-prometheus"
  prometheus_conf       = merge(local.prometheus_conf_defaults, var.prometheus_conf)

  prometheus_conf_defaults = {
    "alertmanager.enabled"                                                 = true
    "operator.enabled"                                                     = true
    "prometheus.enabled"                                                   = true
    "prometheus.ingress.enabled"                                           = false
    "prometheus.enableAdminAPI"                                            = true
    "prometheus.ingress.certManager"                                       = true
    "prometheus.ingress.hostname"                                          = "prometheus.${var.domains[0]}"
    "prometheus.ingress.tls"                                               = true
    "prometheus.persistence.enabled"                                       = true
    "prometheus.persistence.size"                                          = "10Gi"
    "prometheus.retention"                                                 = "10d" # How long to retain metrics TODO: set variables
    "prometheus.disableCompaction"                                         = true
    "prometheus.externalLabels.cluster"                                    = var.cluster_name
    "prometheus.thanos.create"                                             = true
    "prometheus.thanos.ingress.enabled"                                    = false # Need for external thanos
    "prometheus.thanos.ingress.certManager"                                = true
    "prometheus.thanos.ingress.hosts[0]"                                   = "thanos-gateway.${var.domains[0]}"
    "prometheus.thanos.ingress.tls[0].secretName"                          = "thanos-gateway-local-tls"
    "prometheus.thanos.ingress.tls[0].hosts[0]"                            = "thanos-gateway.${var.domains[0]}"
    "prometheus.thanos.objectStorageConfig.secretName"                     = local.storage > 0 ? kubernetes_secret.thanos_objstore[0].metadata.0.name : kubernetes_secret.s3_objstore[0].metadata.0.name
    "prometheus.thanos.objectStorageConfig.secretKey"                      = "objstore.yml"
    "prometheus.serviceAccount.name"                                       = local.thanos_name
    "prometheus.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" = module.iam_assumable_role_admin.this_iam_role_arn
    "namespace"                                                            = local.namespace
  }

  #Thanos
  thanos_name       = "thanos"
  thanos_repository = "https://charts.bitnami.com/bitnami"
  thanos_chart      = "thanos"
  thanos_conf       = merge(local.thanos_conf_defaults, var.thanos_conf)
  thanos_password   = var.thanos_password == "" ? random_password.thanos_password.result : var.thanos_password

  thanos_conf_defaults = {
    "query.sdConfig" = yamlencode(
      [{
        "targets" = ["kube-prometheus-prometheus-thanos:10901"]
      }]
    )
    "query.enabled"                     = "true"
    "query.ingress.enabled"             = "false"
    "query.ingress.grpc.enabled"        = "false"
    "queryFrontend.enabled"             = "true"
    "queryFrontend.ingress.enabled"     = "true"
    "queryFrontend.ingress.certManager" = "true"
    "queryFrontend.ingress.hostname"    = "thanos.${var.domains[0]}"
    "queryFrontend.ingress.tls"         = "true"
    "bucketweb.enabled"                 = "true"
    "compactor.enabled"                 = "true"
    "compactor.retentionResolutionRaw"  = "30d"
    "compactor.retentionResolution5m"   = "30d"
    "compactor.retentionResolution1h"   = "10y"
    "compactor.persistence.size"        = "10Gi"
    "storegateway.enabled"              = "true"
    "ruler.enabled"                     = "false"
    "receive.enabled"                   = "true"
    "metrics.enabled"                   = "true"
    "minio.enabled"                     = local.storage > 0 ? "true" : "false"
    "minio.accessKey.password"          = "thanosStorage"
    "minio.secretKey.password"          = local.storage
    "existingObjstoreSecret"            = local.storage > 0 ? kubernetes_secret.thanos_objstore[0].metadata.0.name : kubernetes_secret.s3_objstore[0].metadata.0.name
    "namespace"                         = local.namespace
    "existingServiceAccount"            = local.thanos_name
  }
}
