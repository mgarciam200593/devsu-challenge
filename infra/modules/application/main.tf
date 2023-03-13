data "aws_lb" "nlb" {
  tags = {
    "Environment" = var.env
  }
}

data "aws_route53_zone" "dns" {
  name         = "accessqlabs.link"
  private_zone = false
}

resource "aws_route53_record" "app_domain" {
  zone_id = data.aws_route53_zone.dns.zone_id
  name    = "devsu-${var.env}.accessqlabs.link"
  type    = "A"

  alias {
    name                   = data.aws_lb.nlb.dns_name
    zone_id                = data.aws_lb.nlb.zone_id
    evaluate_target_health = true
  }
}

resource "kubernetes_namespace_v1" "namespace_app" {
    metadata {
        name = var.env
    }
}

resource "kubernetes_deployment_v1" "deployment_app" {
    metadata {
        name = "flask-api"
        namespace = kubernetes_namespace_v1.namespace_app.metadata[0].name
    }
    spec {
        replicas = 2
        selector {
            match_labels = {
                app = "flask-api-${var.env}"
            }
        }
        template {
            metadata {
                labels = {
                    app = "flask-api-${var.env}"
                }
            }
            spec {
                container {
                    image = "public.ecr.aws/t1c2g3k3/test-devsu:${var.image_tag}"
                    name = "api-flask"
                    resources {
                        limits = {
                            cpu = "100m"
                        }
                        requests = {
                            cpu = "50m"
                        }
                    }
                }
            }
        }
    }
}

resource "kubernetes_service_v1" "service_app" {
    metadata {
        name = "flask-api-svc"
        namespace = kubernetes_namespace_v1.namespace_app.metadata[0].name
    }
    spec {
        selector = {
            app = "flask-api-${var.env}"
        }
        port {
            port        = 8080
            target_port = 5000
            protocol = "TCP"
        }
        type = "ClusterIP"
    }
}

resource "kubernetes_manifest" "jwtsecret_app" {
    manifest = yamldecode(
<<-EOF
apiVersion: v1
kind: Secret
metadata:
  name: jwk-secret
  namespace: ${kubernetes_namespace_v1.namespace_app.metadata[0].name}
type: nginx.org/jwk
data:
  jwk: eyJrZXlzIjoKICAgIFt7CiAgICAgICAgImsiOiJabUZ1ZEdGemRHbGphbmQwIiwKICAgICAgICAia3R5Ijoib2N0IiwKICAgICAgICAia2lkIjoiMDAwMSIKICAgIH1dCn0K
EOF
    )
}

resource "kubernetes_manifest" "jwtpolicy_app" {
    manifest = yamldecode(
<<-EOF
apiVersion: k8s.nginx.org/v1
kind: Policy
metadata:
  name: jwt-policy
  namespace: ${kubernetes_namespace_v1.namespace_app.metadata[0].name}
spec:
  jwt:
    realm: devsu
    secret: jwk-secret
    token: $http_x_jwt_key
EOF
    )
    timeouts {
      create = "1m"
    }
}

resource "kubernetes_manifest" "virtualserver_app" {
    manifest = yamldecode(
<<-EOF
apiVersion: k8s.nginx.org/v1
kind: VirtualServer
metadata:
  name: devsu-app-vs
  namespace: ${kubernetes_namespace_v1.namespace_app.metadata[0].name}
spec:
  http-snippets: |
    map $http_x_parse_rest_api_key $api_realm {
      default "";
      "2f5ae96c-b558-4c7b-a590-a501ae1c3f6c"  "client_one";
    }
  server-snippets: |
    location = /authorize_apikey {
      internal;
      if ($http_x_parse_rest_api_key = "") {
        return 401; # Unauthorized
      }
      if ($api_realm = "") {
          return 403; # Forbidden
      }
      return 204;
    }
    add_header Access-Control-Allow-Headers "X-Parse-REST-API-Key, Authorization";
    auth_request /authorize_apikey;
  host: devsu-${var.env}.accessqlabs.link
  upstreams:
  - name: flask-api
    service: flask-api-svc
    port: 8080
  routes:
  - path: /DevOps
    policies:
    - name: jwt-policy
    errorPages:
    - codes: [401, 403]
      return:
        code: 200
        type: application/json
        body: |
          {\"msg\": \"You don't have permission to do this\"}
    matches:
    - conditions:
      - variable: $request_method
        value: POST
      action:
        proxy:
          upstream: flask-api
          rewritePath: /DevOps
    location-snippets: |
      proxy_ssl_verify  off;
    action:
      return:
        code: 200
        type: text/plain
        body: "ERROR"
EOF
    )
    timeouts {
      create = "1m"
    }
}