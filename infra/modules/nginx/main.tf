data "aws_eks_cluster" "eks" {
  name = var.cluster_name
}

data "aws_subnets" "subnets" {
  tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_iam_role" "eks_nodes" {
  name = "eks_nodes_devsu_role_${var.env}"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = data.aws_eks_cluster.eks.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.eks_nodes.arn

  subnet_ids = data.aws_subnets.subnets.ids

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.nodes-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.nodes-AmazonEC2ContainerRegistryReadOnly
  ]
}

data "aws_route53_zone" "dns" {
  name         = "accessqlabs.link"
  private_zone = false
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "devsu-${var.env}.accessqlabs.link"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "example" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.dns.zone_id
}

resource "kubernetes_namespace_v1" "namespace_nginx" {
  metadata {
    name = var.nginx_ns
  }
}

resource "kubernetes_service_account_v1" "serviceaccount_nginx" {
  metadata {
    name      = var.nginx_ns
    namespace = kubernetes_namespace_v1.namespace_nginx.metadata[0].name
  }
}

resource "kubernetes_cluster_role_v1" "cluster_role_nginx" {
  metadata {
    name = var.nginx_ns
  }

  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch", "update", "create"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "list", "patch"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "list", "watch", "update", "create"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["list", "watch", "get"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses/status"]
    verbs      = ["update"]
  }

  rule {
    api_groups = ["k8s.nginx.org"]
    resources  = ["virtualservers", "virtualserverroutes", "globalconfigurations", "transportservers", "policies"]
    verbs      = ["list", "watch", "get"]
  }

  rule {
    api_groups = ["k8s.nginx.org"]
    resources  = ["virtualservers/status", "virtualserverroutes/status", "globalconfigurations/status", "transportservers/status", "policies/status"]
    verbs      = ["update"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingressclasses"]
    verbs      = ["get"]
  }

  rule {
    api_groups = ["cis.f5.com"]
    resources  = ["ingresslinks"]
    verbs      = ["list", "watch", "get"]
  }

  rule {
    api_groups = ["cert-manager.io"]
    resources  = ["certificates"]
    verbs      = ["list", "watch", "get", "update", "create", "delete"]
  }

  rule {
    api_groups = ["externaldns.nginx.org"]
    resources  = ["dnsendpoints"]
    verbs      = ["list", "watch", "get", "update", "create", "delete"]
  }

  rule {
    api_groups = ["externaldns.nginx.org"]
    resources  = ["dnsendpoints/status"]
    verbs      = ["update"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "cluster_role_binding_nginx" {
  metadata {
    name = var.nginx_ns
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.cluster_role_nginx.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.serviceaccount_nginx.metadata[0].name
    namespace = kubernetes_namespace_v1.namespace_nginx.metadata[0].name
  }
}

resource "kubernetes_manifest" "default_server_secret_nginx" {
  manifest = yamldecode(
<<-EOF
apiVersion: v1
kind: Secret
metadata:
  name: default-server-secret
  namespace: ${var.nginx_ns}
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUN2akNDQWFZQ0NRREFPRjl0THNhWFhEQU5CZ2txaGtpRzl3MEJBUXNGQURBaE1SOHdIUVlEVlFRRERCWk8KUjBsT1dFbHVaM0psYzNORGIyNTBjbTlzYkdWeU1CNFhEVEU0TURreE1qRTRNRE16TlZvWERUSXpNRGt4TVRFNApNRE16TlZvd0lURWZNQjBHQTFVRUF3d1dUa2RKVGxoSmJtZHlaWE56UTI5dWRISnZiR3hsY2pDQ0FTSXdEUVlKCktvWklodmNOQVFFQkJRQURnZ0VQQURDQ0FRb0NnZ0VCQUwvN2hIUEtFWGRMdjNyaUM3QlBrMTNpWkt5eTlyQ08KR2xZUXYyK2EzUDF0azIrS3YwVGF5aGRCbDRrcnNUcTZzZm8vWUk1Y2Vhbkw4WGM3U1pyQkVRYm9EN2REbWs1Qgo4eDZLS2xHWU5IWlg0Rm5UZ0VPaStlM2ptTFFxRlBSY1kzVnNPazFFeUZBL0JnWlJVbkNHZUtGeERSN0tQdGhyCmtqSXVuektURXUyaDU4Tlp0S21ScUJHdDEwcTNRYzhZT3ExM2FnbmovUWRjc0ZYYTJnMjB1K1lYZDdoZ3krZksKWk4vVUkxQUQ0YzZyM1lma1ZWUmVHd1lxQVp1WXN2V0RKbW1GNWRwdEMzN011cDBPRUxVTExSakZJOTZXNXIwSAo1TmdPc25NWFJNV1hYVlpiNWRxT3R0SmRtS3FhZ25TZ1JQQVpQN2MwQjFQU2FqYzZjNGZRVXpNQ0F3RUFBVEFOCkJna3Foa2lHOXcwQkFRc0ZBQU9DQVFFQWpLb2tRdGRPcEsrTzhibWVPc3lySmdJSXJycVFVY2ZOUitjb0hZVUoKdGhrYnhITFMzR3VBTWI5dm15VExPY2xxeC9aYzJPblEwMEJCLzlTb0swcitFZ1U2UlVrRWtWcitTTFA3NTdUWgozZWI4dmdPdEduMS9ienM3bzNBaS9kclkrcUI5Q2k1S3lPc3FHTG1US2xFaUtOYkcyR1ZyTWxjS0ZYQU80YTY3Cklnc1hzYktNbTQwV1U3cG9mcGltU1ZmaXFSdkV5YmN3N0NYODF6cFErUyt1eHRYK2VBZ3V0NHh3VlI5d2IyVXYKelhuZk9HbWhWNThDd1dIQnNKa0kxNXhaa2VUWXdSN0diaEFMSkZUUkk3dkhvQXprTWIzbjAxQjQyWjNrN3RXNQpJUDFmTlpIOFUvOWxiUHNoT21FRFZkdjF5ZytVRVJxbStGSis2R0oxeFJGcGZnPT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
  tls.key: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFcEFJQkFBS0NBUUVBdi91RWM4b1JkMHUvZXVJTHNFK1RYZUprckxMMnNJNGFWaEMvYjVyYy9XMlRiNHEvClJOcktGMEdYaVN1eE9ycXgrajlnamx4NXFjdnhkenRKbXNFUkJ1Z1B0ME9hVGtIekhvb3FVWmcwZGxmZ1dkT0EKUTZMNTdlT1l0Q29VOUZ4amRXdzZUVVRJVUQ4R0JsRlNjSVo0b1hFTkhzbysyR3VTTWk2Zk1wTVM3YUhudzFtMApxWkdvRWEzWFNyZEJ6eGc2clhkcUNlUDlCMXl3VmRyYURiUzc1aGQzdUdETDU4cGszOVFqVUFQaHpxdmRoK1JWClZGNGJCaW9CbTVpeTlZTW1hWVhsMm0wTGZzeTZuUTRRdFFzdEdNVWozcGJtdlFmazJBNnljeGRFeFpkZFZsdmwKMm82MjBsMllxcHFDZEtCRThCay90elFIVTlKcU56cHpoOUJUTXdJREFRQUJBb0lCQVFDZklHbXowOHhRVmorNwpLZnZJUXQwQ0YzR2MxNld6eDhVNml4MHg4Mm15d1kxUUNlL3BzWE9LZlRxT1h1SENyUlp5TnUvZ2IvUUQ4bUFOCmxOMjRZTWl0TWRJODg5TEZoTkp3QU5OODJDeTczckM5bzVvUDlkazAvYzRIbjAzSkVYNzZ5QjgzQm9rR1FvYksKMjhMNk0rdHUzUmFqNjd6Vmc2d2szaEhrU0pXSzBwV1YrSjdrUkRWYmhDYUZhNk5nMUZNRWxhTlozVDhhUUtyQgpDUDNDeEFTdjYxWTk5TEI4KzNXWVFIK3NYaTVGM01pYVNBZ1BkQUk3WEh1dXFET1lvMU5PL0JoSGt1aVg2QnRtCnorNTZud2pZMy8yUytSRmNBc3JMTnIwMDJZZi9oY0IraVlDNzVWYmcydVd6WTY3TWdOTGQ5VW9RU3BDRkYrVm4KM0cyUnhybnhBb0dCQU40U3M0ZVlPU2huMVpQQjdhTUZsY0k2RHR2S2ErTGZTTXFyY2pOZjJlSEpZNnhubmxKdgpGenpGL2RiVWVTbWxSekR0WkdlcXZXaHFISy9iTjIyeWJhOU1WMDlRQ0JFTk5jNmtWajJTVHpUWkJVbEx4QzYrCk93Z0wyZHhKendWelU0VC84ajdHalRUN05BZVpFS2FvRHFyRG5BYWkyaW5oZU1JVWZHRXFGKzJyQW9HQkFOMVAKK0tZL0lsS3RWRzRKSklQNzBjUis3RmpyeXJpY05iWCtQVzUvOXFHaWxnY2grZ3l4b25BWlBpd2NpeDN3QVpGdwpaZC96ZFB2aTBkWEppc1BSZjRMazg5b2pCUmpiRmRmc2l5UmJYbyt3TFU4NUhRU2NGMnN5aUFPaTVBRHdVU0FkCm45YWFweUNweEFkREtERHdObit3ZFhtaTZ0OHRpSFRkK3RoVDhkaVpBb0dCQUt6Wis1bG9OOTBtYlF4VVh5YUwKMjFSUm9tMGJjcndsTmVCaWNFSmlzaEhYa2xpSVVxZ3hSZklNM2hhUVRUcklKZENFaHFsV01aV0xPb2I2NTNyZgo3aFlMSXM1ZUtka3o0aFRVdnpldm9TMHVXcm9CV2xOVHlGanIrSWhKZnZUc0hpOGdsU3FkbXgySkJhZUFVWUNXCndNdlQ4NmNLclNyNkQrZG8wS05FZzFsL0FvR0FlMkFVdHVFbFNqLzBmRzgrV3hHc1RFV1JqclRNUzRSUjhRWXQKeXdjdFA4aDZxTGxKUTRCWGxQU05rMXZLTmtOUkxIb2pZT2pCQTViYjhibXNVU1BlV09NNENoaFJ4QnlHbmR2eAphYkJDRkFwY0IvbEg4d1R0alVZYlN5T294ZGt5OEp0ek90ajJhS0FiZHd6NlArWDZDODhjZmxYVFo5MWpYL3RMCjF3TmRKS2tDZ1lCbyt0UzB5TzJ2SWFmK2UwSkN5TGhzVDQ5cTN3Zis2QWVqWGx2WDJ1VnRYejN5QTZnbXo5aCsKcDNlK2JMRUxwb3B0WFhNdUFRR0xhUkcrYlNNcjR5dERYbE5ZSndUeThXczNKY3dlSTdqZVp2b0ZpbmNvVlVIMwphdmxoTUVCRGYxSjltSDB5cDBwWUNaS2ROdHNvZEZtQktzVEtQMjJhTmtsVVhCS3gyZzR6cFE9PQotLS0tLUVORCBSU0EgUFJJVkFURSBLRVktLS0tLQo=
EOF
  )
}

resource "kubernetes_manifest" "configmap_nginx" {
  manifest = yamldecode(
<<-EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: nginx-config
  namespace: ${var.nginx_ns}
data:
  ssl-protocols: "TLSv1.3"
EOF
  )
}

resource "kubernetes_ingress_class_v1" "ingress_class_nginx" {
  metadata {
    name = "nginx"
  }

  spec {
    controller = "nginx.org/ingress-controller"
  }
}

resource "kubernetes_manifest" "crd_virtualservers_nginx" {
  manifest = yamldecode(
    <<-EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.11.1
  creationTimestamp: null
  name: virtualservers.k8s.nginx.org
spec:
  group: k8s.nginx.org
  names:
    kind: VirtualServer
    listKind: VirtualServerList
    plural: virtualservers
    shortNames:
      - vs
    singular: virtualserver
  scope: Namespaced
  versions:
    - additionalPrinterColumns:
        - description: Current state of the VirtualServer. If the resource has a valid status, it means it has been validated and accepted by the Ingress Controller.
          jsonPath: .status.state
          name: State
          type: string
        - jsonPath: .spec.host
          name: Host
          type: string
        - jsonPath: .status.externalEndpoints[*].ip
          name: IP
          type: string
        - jsonPath: .status.externalEndpoints[*].hostname
          name: ExternalHostname
          priority: 1
          type: string
        - jsonPath: .status.externalEndpoints[*].ports
          name: Ports
          type: string
        - jsonPath: .metadata.creationTimestamp
          name: Age
          type: date
      name: v1
      schema:
        openAPIV3Schema:
          description: VirtualServer defines the VirtualServer resource.
          type: object
          properties:
            apiVersion:
              description: 'APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
              type: string
            kind:
              description: 'Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
              type: string
            metadata:
              type: object
            spec:
              description: VirtualServerSpec is the spec of the VirtualServer resource.
              type: object
              properties:
                dos:
                  type: string
                externalDNS:
                  description: ExternalDNS defines externaldns sub-resource of a virtual server.
                  type: object
                  properties:
                    enable:
                      type: boolean
                    labels:
                      description: Labels stores labels defined for the Endpoint
                      type: object
                      additionalProperties:
                        type: string
                    providerSpecific:
                      description: ProviderSpecific stores provider specific config
                      type: array
                      items:
                        description: ProviderSpecificProperty defines specific property for using with ExternalDNS sub-resource.
                        type: object
                        properties:
                          name:
                            description: Name of the property
                            type: string
                          value:
                            description: Value of the property
                            type: string
                    recordTTL:
                      description: TTL for the record
                      type: integer
                      format: int64
                    recordType:
                      type: string
                host:
                  type: string
                http-snippets:
                  type: string
                ingressClassName:
                  type: string
                policies:
                  type: array
                  items:
                    description: PolicyReference references a policy by name and an optional namespace.
                    type: object
                    properties:
                      name:
                        type: string
                      namespace:
                        type: string
                routes:
                  type: array
                  items:
                    description: Route defines a route.
                    type: object
                    properties:
                      action:
                        description: Action defines an action.
                        type: object
                        properties:
                          pass:
                            type: string
                          proxy:
                            description: ActionProxy defines a proxy in an Action.
                            type: object
                            properties:
                              requestHeaders:
                                description: ProxyRequestHeaders defines the request headers manipulation in an ActionProxy.
                                type: object
                                properties:
                                  pass:
                                    type: boolean
                                  set:
                                    type: array
                                    items:
                                      description: Header defines an HTTP Header.
                                      type: object
                                      properties:
                                        name:
                                          type: string
                                        value:
                                          type: string
                              responseHeaders:
                                description: ProxyResponseHeaders defines the response headers manipulation in an ActionProxy.
                                type: object
                                properties:
                                  add:
                                    type: array
                                    items:
                                      description: AddHeader defines an HTTP Header with an optional Always field to use with the add_header NGINX directive.
                                      type: object
                                      properties:
                                        always:
                                          type: boolean
                                        name:
                                          type: string
                                        value:
                                          type: string
                                  hide:
                                    type: array
                                    items:
                                      type: string
                                  ignore:
                                    type: array
                                    items:
                                      type: string
                                  pass:
                                    type: array
                                    items:
                                      type: string
                              rewritePath:
                                type: string
                              upstream:
                                type: string
                          redirect:
                            description: ActionRedirect defines a redirect in an Action.
                            type: object
                            properties:
                              code:
                                type: integer
                              url:
                                type: string
                          return:
                            description: ActionReturn defines a return in an Action.
                            type: object
                            properties:
                              body:
                                type: string
                              code:
                                type: integer
                              type:
                                type: string
                      dos:
                        type: string
                      errorPages:
                        type: array
                        items:
                          description: ErrorPage defines an ErrorPage in a Route.
                          type: object
                          properties:
                            codes:
                              type: array
                              items:
                                type: integer
                            redirect:
                              description: ErrorPageRedirect defines a redirect for an ErrorPage.
                              type: object
                              properties:
                                code:
                                  type: integer
                                url:
                                  type: string
                            return:
                              description: ErrorPageReturn defines a return for an ErrorPage.
                              type: object
                              properties:
                                body:
                                  type: string
                                code:
                                  type: integer
                                headers:
                                  type: array
                                  items:
                                    description: Header defines an HTTP Header.
                                    type: object
                                    properties:
                                      name:
                                        type: string
                                      value:
                                        type: string
                                type:
                                  type: string
                      location-snippets:
                        type: string
                      matches:
                        type: array
                        items:
                          description: Match defines a match.
                          type: object
                          properties:
                            action:
                              description: Action defines an action.
                              type: object
                              properties:
                                pass:
                                  type: string
                                proxy:
                                  description: ActionProxy defines a proxy in an Action.
                                  type: object
                                  properties:
                                    requestHeaders:
                                      description: ProxyRequestHeaders defines the request headers manipulation in an ActionProxy.
                                      type: object
                                      properties:
                                        pass:
                                          type: boolean
                                        set:
                                          type: array
                                          items:
                                            description: Header defines an HTTP Header.
                                            type: object
                                            properties:
                                              name:
                                                type: string
                                              value:
                                                type: string
                                    responseHeaders:
                                      description: ProxyResponseHeaders defines the response headers manipulation in an ActionProxy.
                                      type: object
                                      properties:
                                        add:
                                          type: array
                                          items:
                                            description: AddHeader defines an HTTP Header with an optional Always field to use with the add_header NGINX directive.
                                            type: object
                                            properties:
                                              always:
                                                type: boolean
                                              name:
                                                type: string
                                              value:
                                                type: string
                                        hide:
                                          type: array
                                          items:
                                            type: string
                                        ignore:
                                          type: array
                                          items:
                                            type: string
                                        pass:
                                          type: array
                                          items:
                                            type: string
                                    rewritePath:
                                      type: string
                                    upstream:
                                      type: string
                                redirect:
                                  description: ActionRedirect defines a redirect in an Action.
                                  type: object
                                  properties:
                                    code:
                                      type: integer
                                    url:
                                      type: string
                                return:
                                  description: ActionReturn defines a return in an Action.
                                  type: object
                                  properties:
                                    body:
                                      type: string
                                    code:
                                      type: integer
                                    type:
                                      type: string
                            conditions:
                              type: array
                              items:
                                description: Condition defines a condition in a MatchRule.
                                type: object
                                properties:
                                  argument:
                                    type: string
                                  cookie:
                                    type: string
                                  header:
                                    type: string
                                  value:
                                    type: string
                                  variable:
                                    type: string
                            splits:
                              type: array
                              items:
                                description: Split defines a split.
                                type: object
                                properties:
                                  action:
                                    description: Action defines an action.
                                    type: object
                                    properties:
                                      pass:
                                        type: string
                                      proxy:
                                        description: ActionProxy defines a proxy in an Action.
                                        type: object
                                        properties:
                                          requestHeaders:
                                            description: ProxyRequestHeaders defines the request headers manipulation in an ActionProxy.
                                            type: object
                                            properties:
                                              pass:
                                                type: boolean
                                              set:
                                                type: array
                                                items:
                                                  description: Header defines an HTTP Header.
                                                  type: object
                                                  properties:
                                                    name:
                                                      type: string
                                                    value:
                                                      type: string
                                          responseHeaders:
                                            description: ProxyResponseHeaders defines the response headers manipulation in an ActionProxy.
                                            type: object
                                            properties:
                                              add:
                                                type: array
                                                items:
                                                  description: AddHeader defines an HTTP Header with an optional Always field to use with the add_header NGINX directive.
                                                  type: object
                                                  properties:
                                                    always:
                                                      type: boolean
                                                    name:
                                                      type: string
                                                    value:
                                                      type: string
                                              hide:
                                                type: array
                                                items:
                                                  type: string
                                              ignore:
                                                type: array
                                                items:
                                                  type: string
                                              pass:
                                                type: array
                                                items:
                                                  type: string
                                          rewritePath:
                                            type: string
                                          upstream:
                                            type: string
                                      redirect:
                                        description: ActionRedirect defines a redirect in an Action.
                                        type: object
                                        properties:
                                          code:
                                            type: integer
                                          url:
                                            type: string
                                      return:
                                        description: ActionReturn defines a return in an Action.
                                        type: object
                                        properties:
                                          body:
                                            type: string
                                          code:
                                            type: integer
                                          type:
                                            type: string
                                  weight:
                                    type: integer
                      path:
                        type: string
                      policies:
                        type: array
                        items:
                          description: PolicyReference references a policy by name and an optional namespace.
                          type: object
                          properties:
                            name:
                              type: string
                            namespace:
                              type: string
                      route:
                        type: string
                      splits:
                        type: array
                        items:
                          description: Split defines a split.
                          type: object
                          properties:
                            action:
                              description: Action defines an action.
                              type: object
                              properties:
                                pass:
                                  type: string
                                proxy:
                                  description: ActionProxy defines a proxy in an Action.
                                  type: object
                                  properties:
                                    requestHeaders:
                                      description: ProxyRequestHeaders defines the request headers manipulation in an ActionProxy.
                                      type: object
                                      properties:
                                        pass:
                                          type: boolean
                                        set:
                                          type: array
                                          items:
                                            description: Header defines an HTTP Header.
                                            type: object
                                            properties:
                                              name:
                                                type: string
                                              value:
                                                type: string
                                    responseHeaders:
                                      description: ProxyResponseHeaders defines the response headers manipulation in an ActionProxy.
                                      type: object
                                      properties:
                                        add:
                                          type: array
                                          items:
                                            description: AddHeader defines an HTTP Header with an optional Always field to use with the add_header NGINX directive.
                                            type: object
                                            properties:
                                              always:
                                                type: boolean
                                              name:
                                                type: string
                                              value:
                                                type: string
                                        hide:
                                          type: array
                                          items:
                                            type: string
                                        ignore:
                                          type: array
                                          items:
                                            type: string
                                        pass:
                                          type: array
                                          items:
                                            type: string
                                    rewritePath:
                                      type: string
                                    upstream:
                                      type: string
                                redirect:
                                  description: ActionRedirect defines a redirect in an Action.
                                  type: object
                                  properties:
                                    code:
                                      type: integer
                                    url:
                                      type: string
                                return:
                                  description: ActionReturn defines a return in an Action.
                                  type: object
                                  properties:
                                    body:
                                      type: string
                                    code:
                                      type: integer
                                    type:
                                      type: string
                            weight:
                              type: integer
                server-snippets:
                  type: string
                tls:
                  description: TLS defines TLS configuration for a VirtualServer.
                  type: object
                  properties:
                    cert-manager:
                      description: CertManager defines a cert manager config for a TLS.
                      type: object
                      properties:
                        cluster-issuer:
                          type: string
                        common-name:
                          type: string
                        duration:
                          type: string
                        issuer:
                          type: string
                        issuer-group:
                          type: string
                        issuer-kind:
                          type: string
                        renew-before:
                          type: string
                        usages:
                          type: string
                    redirect:
                      description: TLSRedirect defines a redirect for a TLS.
                      type: object
                      properties:
                        basedOn:
                          type: string
                        code:
                          type: integer
                        enable:
                          type: boolean
                    secret:
                      type: string
                upstreams:
                  type: array
                  items:
                    description: Upstream defines an upstream.
                    type: object
                    properties:
                      buffer-size:
                        type: string
                      buffering:
                        type: boolean
                      buffers:
                        description: UpstreamBuffers defines Buffer Configuration for an Upstream.
                        type: object
                        properties:
                          number:
                            type: integer
                          size:
                            type: string
                      client-max-body-size:
                        type: string
                      connect-timeout:
                        type: string
                      fail-timeout:
                        type: string
                      healthCheck:
                        description: HealthCheck defines the parameters for active Upstream HealthChecks.
                        type: object
                        properties:
                          connect-timeout:
                            type: string
                          enable:
                            type: boolean
                          fails:
                            type: integer
                          grpcService:
                            type: string
                          grpcStatus:
                            type: integer
                          headers:
                            type: array
                            items:
                              description: Header defines an HTTP Header.
                              type: object
                              properties:
                                name:
                                  type: string
                                value:
                                  type: string
                          interval:
                            type: string
                          jitter:
                            type: string
                          mandatory:
                            type: boolean
                          passes:
                            type: integer
                          path:
                            type: string
                          persistent:
                            type: boolean
                          port:
                            type: integer
                          read-timeout:
                            type: string
                          send-timeout:
                            type: string
                          statusMatch:
                            type: string
                          tls:
                            description: UpstreamTLS defines a TLS configuration for an Upstream.
                            type: object
                            properties:
                              enable:
                                type: boolean
                      keepalive:
                        type: integer
                      lb-method:
                        type: string
                      max-conns:
                        type: integer
                      max-fails:
                        type: integer
                      name:
                        type: string
                      next-upstream:
                        type: string
                      next-upstream-timeout:
                        type: string
                      next-upstream-tries:
                        type: integer
                      ntlm:
                        type: boolean
                      port:
                        type: integer
                      queue:
                        description: UpstreamQueue defines Queue Configuration for an Upstream.
                        type: object
                        properties:
                          size:
                            type: integer
                          timeout:
                            type: string
                      read-timeout:
                        type: string
                      send-timeout:
                        type: string
                      service:
                        type: string
                      sessionCookie:
                        description: SessionCookie defines the parameters for session persistence.
                        type: object
                        properties:
                          domain:
                            type: string
                          enable:
                            type: boolean
                          expires:
                            type: string
                          httpOnly:
                            type: boolean
                          name:
                            type: string
                          path:
                            type: string
                          secure:
                            type: boolean
                      slow-start:
                        type: string
                      subselector:
                        type: object
                        additionalProperties:
                          type: string
                      tls:
                        description: UpstreamTLS defines a TLS configuration for an Upstream.
                        type: object
                        properties:
                          enable:
                            type: boolean
                      type:
                        type: string
                      use-cluster-ip:
                        type: boolean
            status:
              description: VirtualServerStatus defines the status for the VirtualServer resource.
              type: object
              properties:
                externalEndpoints:
                  type: array
                  items:
                    description: ExternalEndpoint defines the IP/ Hostname and ports used to connect to this resource.
                    type: object
                    properties:
                      hostname:
                        type: string
                      ip:
                        type: string
                      ports:
                        type: string
                message:
                  type: string
                reason:
                  type: string
                state:
                  type: string
      served: true
      storage: true
      subresources:
        status: {}
EOF
  )
}

resource "kubernetes_manifest" "crd_virtualserverroutes_nginx" {
  manifest = yamldecode(
    <<-EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.11.1
  creationTimestamp: null
  name: virtualserverroutes.k8s.nginx.org
spec:
  group: k8s.nginx.org
  names:
    kind: VirtualServerRoute
    listKind: VirtualServerRouteList
    plural: virtualserverroutes
    shortNames:
      - vsr
    singular: virtualserverroute
  scope: Namespaced
  versions:
    - additionalPrinterColumns:
        - description: Current state of the VirtualServerRoute. If the resource has a valid status, it means it has been validated and accepted by the Ingress Controller.
          jsonPath: .status.state
          name: State
          type: string
        - jsonPath: .spec.host
          name: Host
          type: string
        - jsonPath: .status.externalEndpoints[*].ip
          name: IP
          type: string
        - jsonPath: .status.externalEndpoints[*].hostname
          name: ExternalHostname
          priority: 1
          type: string
        - jsonPath: .status.externalEndpoints[*].ports
          name: Ports
          type: string
        - jsonPath: .metadata.creationTimestamp
          name: Age
          type: date
      name: v1
      schema:
        openAPIV3Schema:
          description: VirtualServerRoute defines the VirtualServerRoute resource.
          type: object
          properties:
            apiVersion:
              description: 'APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
              type: string
            kind:
              description: 'Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
              type: string
            metadata:
              type: object
            spec:
              description: VirtualServerRouteSpec is the spec of the VirtualServerRoute resource.
              type: object
              properties:
                host:
                  type: string
                ingressClassName:
                  type: string
                subroutes:
                  type: array
                  items:
                    description: Route defines a route.
                    type: object
                    properties:
                      action:
                        description: Action defines an action.
                        type: object
                        properties:
                          pass:
                            type: string
                          proxy:
                            description: ActionProxy defines a proxy in an Action.
                            type: object
                            properties:
                              requestHeaders:
                                description: ProxyRequestHeaders defines the request headers manipulation in an ActionProxy.
                                type: object
                                properties:
                                  pass:
                                    type: boolean
                                  set:
                                    type: array
                                    items:
                                      description: Header defines an HTTP Header.
                                      type: object
                                      properties:
                                        name:
                                          type: string
                                        value:
                                          type: string
                              responseHeaders:
                                description: ProxyResponseHeaders defines the response headers manipulation in an ActionProxy.
                                type: object
                                properties:
                                  add:
                                    type: array
                                    items:
                                      description: AddHeader defines an HTTP Header with an optional Always field to use with the add_header NGINX directive.
                                      type: object
                                      properties:
                                        always:
                                          type: boolean
                                        name:
                                          type: string
                                        value:
                                          type: string
                                  hide:
                                    type: array
                                    items:
                                      type: string
                                  ignore:
                                    type: array
                                    items:
                                      type: string
                                  pass:
                                    type: array
                                    items:
                                      type: string
                              rewritePath:
                                type: string
                              upstream:
                                type: string
                          redirect:
                            description: ActionRedirect defines a redirect in an Action.
                            type: object
                            properties:
                              code:
                                type: integer
                              url:
                                type: string
                          return:
                            description: ActionReturn defines a return in an Action.
                            type: object
                            properties:
                              body:
                                type: string
                              code:
                                type: integer
                              type:
                                type: string
                      dos:
                        type: string
                      errorPages:
                        type: array
                        items:
                          description: ErrorPage defines an ErrorPage in a Route.
                          type: object
                          properties:
                            codes:
                              type: array
                              items:
                                type: integer
                            redirect:
                              description: ErrorPageRedirect defines a redirect for an ErrorPage.
                              type: object
                              properties:
                                code:
                                  type: integer
                                url:
                                  type: string
                            return:
                              description: ErrorPageReturn defines a return for an ErrorPage.
                              type: object
                              properties:
                                body:
                                  type: string
                                code:
                                  type: integer
                                headers:
                                  type: array
                                  items:
                                    description: Header defines an HTTP Header.
                                    type: object
                                    properties:
                                      name:
                                        type: string
                                      value:
                                        type: string
                                type:
                                  type: string
                      location-snippets:
                        type: string
                      matches:
                        type: array
                        items:
                          description: Match defines a match.
                          type: object
                          properties:
                            action:
                              description: Action defines an action.
                              type: object
                              properties:
                                pass:
                                  type: string
                                proxy:
                                  description: ActionProxy defines a proxy in an Action.
                                  type: object
                                  properties:
                                    requestHeaders:
                                      description: ProxyRequestHeaders defines the request headers manipulation in an ActionProxy.
                                      type: object
                                      properties:
                                        pass:
                                          type: boolean
                                        set:
                                          type: array
                                          items:
                                            description: Header defines an HTTP Header.
                                            type: object
                                            properties:
                                              name:
                                                type: string
                                              value:
                                                type: string
                                    responseHeaders:
                                      description: ProxyResponseHeaders defines the response headers manipulation in an ActionProxy.
                                      type: object
                                      properties:
                                        add:
                                          type: array
                                          items:
                                            description: AddHeader defines an HTTP Header with an optional Always field to use with the add_header NGINX directive.
                                            type: object
                                            properties:
                                              always:
                                                type: boolean
                                              name:
                                                type: string
                                              value:
                                                type: string
                                        hide:
                                          type: array
                                          items:
                                            type: string
                                        ignore:
                                          type: array
                                          items:
                                            type: string
                                        pass:
                                          type: array
                                          items:
                                            type: string
                                    rewritePath:
                                      type: string
                                    upstream:
                                      type: string
                                redirect:
                                  description: ActionRedirect defines a redirect in an Action.
                                  type: object
                                  properties:
                                    code:
                                      type: integer
                                    url:
                                      type: string
                                return:
                                  description: ActionReturn defines a return in an Action.
                                  type: object
                                  properties:
                                    body:
                                      type: string
                                    code:
                                      type: integer
                                    type:
                                      type: string
                            conditions:
                              type: array
                              items:
                                description: Condition defines a condition in a MatchRule.
                                type: object
                                properties:
                                  argument:
                                    type: string
                                  cookie:
                                    type: string
                                  header:
                                    type: string
                                  value:
                                    type: string
                                  variable:
                                    type: string
                            splits:
                              type: array
                              items:
                                description: Split defines a split.
                                type: object
                                properties:
                                  action:
                                    description: Action defines an action.
                                    type: object
                                    properties:
                                      pass:
                                        type: string
                                      proxy:
                                        description: ActionProxy defines a proxy in an Action.
                                        type: object
                                        properties:
                                          requestHeaders:
                                            description: ProxyRequestHeaders defines the request headers manipulation in an ActionProxy.
                                            type: object
                                            properties:
                                              pass:
                                                type: boolean
                                              set:
                                                type: array
                                                items:
                                                  description: Header defines an HTTP Header.
                                                  type: object
                                                  properties:
                                                    name:
                                                      type: string
                                                    value:
                                                      type: string
                                          responseHeaders:
                                            description: ProxyResponseHeaders defines the response headers manipulation in an ActionProxy.
                                            type: object
                                            properties:
                                              add:
                                                type: array
                                                items:
                                                  description: AddHeader defines an HTTP Header with an optional Always field to use with the add_header NGINX directive.
                                                  type: object
                                                  properties:
                                                    always:
                                                      type: boolean
                                                    name:
                                                      type: string
                                                    value:
                                                      type: string
                                              hide:
                                                type: array
                                                items:
                                                  type: string
                                              ignore:
                                                type: array
                                                items:
                                                  type: string
                                              pass:
                                                type: array
                                                items:
                                                  type: string
                                          rewritePath:
                                            type: string
                                          upstream:
                                            type: string
                                      redirect:
                                        description: ActionRedirect defines a redirect in an Action.
                                        type: object
                                        properties:
                                          code:
                                            type: integer
                                          url:
                                            type: string
                                      return:
                                        description: ActionReturn defines a return in an Action.
                                        type: object
                                        properties:
                                          body:
                                            type: string
                                          code:
                                            type: integer
                                          type:
                                            type: string
                                  weight:
                                    type: integer
                      path:
                        type: string
                      policies:
                        type: array
                        items:
                          description: PolicyReference references a policy by name and an optional namespace.
                          type: object
                          properties:
                            name:
                              type: string
                            namespace:
                              type: string
                      route:
                        type: string
                      splits:
                        type: array
                        items:
                          description: Split defines a split.
                          type: object
                          properties:
                            action:
                              description: Action defines an action.
                              type: object
                              properties:
                                pass:
                                  type: string
                                proxy:
                                  description: ActionProxy defines a proxy in an Action.
                                  type: object
                                  properties:
                                    requestHeaders:
                                      description: ProxyRequestHeaders defines the request headers manipulation in an ActionProxy.
                                      type: object
                                      properties:
                                        pass:
                                          type: boolean
                                        set:
                                          type: array
                                          items:
                                            description: Header defines an HTTP Header.
                                            type: object
                                            properties:
                                              name:
                                                type: string
                                              value:
                                                type: string
                                    responseHeaders:
                                      description: ProxyResponseHeaders defines the response headers manipulation in an ActionProxy.
                                      type: object
                                      properties:
                                        add:
                                          type: array
                                          items:
                                            description: AddHeader defines an HTTP Header with an optional Always field to use with the add_header NGINX directive.
                                            type: object
                                            properties:
                                              always:
                                                type: boolean
                                              name:
                                                type: string
                                              value:
                                                type: string
                                        hide:
                                          type: array
                                          items:
                                            type: string
                                        ignore:
                                          type: array
                                          items:
                                            type: string
                                        pass:
                                          type: array
                                          items:
                                            type: string
                                    rewritePath:
                                      type: string
                                    upstream:
                                      type: string
                                redirect:
                                  description: ActionRedirect defines a redirect in an Action.
                                  type: object
                                  properties:
                                    code:
                                      type: integer
                                    url:
                                      type: string
                                return:
                                  description: ActionReturn defines a return in an Action.
                                  type: object
                                  properties:
                                    body:
                                      type: string
                                    code:
                                      type: integer
                                    type:
                                      type: string
                            weight:
                              type: integer
                upstreams:
                  type: array
                  items:
                    description: Upstream defines an upstream.
                    type: object
                    properties:
                      buffer-size:
                        type: string
                      buffering:
                        type: boolean
                      buffers:
                        description: UpstreamBuffers defines Buffer Configuration for an Upstream.
                        type: object
                        properties:
                          number:
                            type: integer
                          size:
                            type: string
                      client-max-body-size:
                        type: string
                      connect-timeout:
                        type: string
                      fail-timeout:
                        type: string
                      healthCheck:
                        description: HealthCheck defines the parameters for active Upstream HealthChecks.
                        type: object
                        properties:
                          connect-timeout:
                            type: string
                          enable:
                            type: boolean
                          fails:
                            type: integer
                          grpcService:
                            type: string
                          grpcStatus:
                            type: integer
                          headers:
                            type: array
                            items:
                              description: Header defines an HTTP Header.
                              type: object
                              properties:
                                name:
                                  type: string
                                value:
                                  type: string
                          interval:
                            type: string
                          jitter:
                            type: string
                          mandatory:
                            type: boolean
                          passes:
                            type: integer
                          path:
                            type: string
                          persistent:
                            type: boolean
                          port:
                            type: integer
                          read-timeout:
                            type: string
                          send-timeout:
                            type: string
                          statusMatch:
                            type: string
                          tls:
                            description: UpstreamTLS defines a TLS configuration for an Upstream.
                            type: object
                            properties:
                              enable:
                                type: boolean
                      keepalive:
                        type: integer
                      lb-method:
                        type: string
                      max-conns:
                        type: integer
                      max-fails:
                        type: integer
                      name:
                        type: string
                      next-upstream:
                        type: string
                      next-upstream-timeout:
                        type: string
                      next-upstream-tries:
                        type: integer
                      ntlm:
                        type: boolean
                      port:
                        type: integer
                      queue:
                        description: UpstreamQueue defines Queue Configuration for an Upstream.
                        type: object
                        properties:
                          size:
                            type: integer
                          timeout:
                            type: string
                      read-timeout:
                        type: string
                      send-timeout:
                        type: string
                      service:
                        type: string
                      sessionCookie:
                        description: SessionCookie defines the parameters for session persistence.
                        type: object
                        properties:
                          domain:
                            type: string
                          enable:
                            type: boolean
                          expires:
                            type: string
                          httpOnly:
                            type: boolean
                          name:
                            type: string
                          path:
                            type: string
                          secure:
                            type: boolean
                      slow-start:
                        type: string
                      subselector:
                        type: object
                        additionalProperties:
                          type: string
                      tls:
                        description: UpstreamTLS defines a TLS configuration for an Upstream.
                        type: object
                        properties:
                          enable:
                            type: boolean
                      type:
                        type: string
                      use-cluster-ip:
                        type: boolean
            status:
              description: VirtualServerRouteStatus defines the status for the VirtualServerRoute resource.
              type: object
              properties:
                externalEndpoints:
                  type: array
                  items:
                    description: ExternalEndpoint defines the IP/ Hostname and ports used to connect to this resource.
                    type: object
                    properties:
                      hostname:
                        type: string
                      ip:
                        type: string
                      ports:
                        type: string
                message:
                  type: string
                reason:
                  type: string
                referencedBy:
                  type: string
                state:
                  type: string
      served: true
      storage: true
      subresources:
        status: {}
EOF
  )
}

resource "kubernetes_manifest" "crd_policies_nginx" {
  manifest = yamldecode(
    <<-EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.11.1
  creationTimestamp: null
  name: policies.k8s.nginx.org
spec:
  group: k8s.nginx.org
  names:
    kind: Policy
    listKind: PolicyList
    plural: policies
    shortNames:
      - pol
    singular: policy
  scope: Namespaced
  versions:
    - additionalPrinterColumns:
        - description: Current state of the Policy. If the resource has a valid status, it means it has been validated and accepted by the Ingress Controller.
          jsonPath: .status.state
          name: State
          type: string
        - jsonPath: .metadata.creationTimestamp
          name: Age
          type: date
      name: v1
      schema:
        openAPIV3Schema:
          description: Policy defines a Policy for VirtualServer and VirtualServerRoute resources.
          type: object
          properties:
            apiVersion:
              description: 'APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
              type: string
            kind:
              description: 'Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
              type: string
            metadata:
              type: object
            spec:
              description: PolicySpec is the spec of the Policy resource. The spec includes multiple fields, where each field represents a different policy. Only one policy (field) is allowed.
              type: object
              properties:
                accessControl:
                  description: AccessControl defines an access policy based on the source IP of a request.
                  type: object
                  properties:
                    allow:
                      type: array
                      items:
                        type: string
                    deny:
                      type: array
                      items:
                        type: string
                basicAuth:
                  description: 'BasicAuth holds HTTP Basic authentication configuration policy status: preview'
                  type: object
                  properties:
                    realm:
                      type: string
                    secret:
                      type: string
                egressMTLS:
                  description: EgressMTLS defines an Egress MTLS policy.
                  type: object
                  properties:
                    ciphers:
                      type: string
                    protocols:
                      type: string
                    serverName:
                      type: boolean
                    sessionReuse:
                      type: boolean
                    sslName:
                      type: string
                    tlsSecret:
                      type: string
                    trustedCertSecret:
                      type: string
                    verifyDepth:
                      type: integer
                    verifyServer:
                      type: boolean
                ingressClassName:
                  type: string
                ingressMTLS:
                  description: IngressMTLS defines an Ingress MTLS policy.
                  type: object
                  properties:
                    clientCertSecret:
                      type: string
                    verifyClient:
                      type: string
                    verifyDepth:
                      type: integer
                jwt:
                  description: JWTAuth holds JWT authentication configuration.
                  type: object
                  properties:
                    jwksURI:
                      type: string
                    keyCache:
                      type: string
                    realm:
                      type: string
                    secret:
                      type: string
                    token:
                      type: string
                oidc:
                  description: OIDC defines an Open ID Connect policy.
                  type: object
                  properties:
                    authEndpoint:
                      type: string
                    clientID:
                      type: string
                    clientSecret:
                      type: string
                    jwksURI:
                      type: string
                    redirectURI:
                      type: string
                    scope:
                      type: string
                    tokenEndpoint:
                      type: string
                    zoneSyncLeeway:
                      type: integer
                rateLimit:
                  description: RateLimit defines a rate limit policy.
                  type: object
                  properties:
                    burst:
                      type: integer
                    delay:
                      type: integer
                    dryRun:
                      type: boolean
                    key:
                      type: string
                    logLevel:
                      type: string
                    noDelay:
                      type: boolean
                    rate:
                      type: string
                    rejectCode:
                      type: integer
                    zoneSize:
                      type: string
                waf:
                  description: WAF defines an WAF policy.
                  type: object
                  properties:
                    apPolicy:
                      type: string
                    enable:
                      type: boolean
                    securityLog:
                      description: SecurityLog defines the security log of a WAF policy.
                      type: object
                      properties:
                        apLogConf:
                          type: string
                        enable:
                          type: boolean
                        logDest:
                          type: string
                    securityLogs:
                      type: array
                      items:
                        description: SecurityLog defines the security log of a WAF policy.
                        type: object
                        properties:
                          apLogConf:
                            type: string
                          enable:
                            type: boolean
                          logDest:
                            type: string
            status:
              description: PolicyStatus is the status of the policy resource
              type: object
              properties:
                message:
                  type: string
                reason:
                  type: string
                state:
                  type: string
      served: true
      storage: true
      subresources:
        status: {}
    - name: v1alpha1
      schema:
        openAPIV3Schema:
          description: Policy defines a Policy for VirtualServer and VirtualServerRoute resources.
          type: object
          properties:
            apiVersion:
              description: 'APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
              type: string
            kind:
              description: 'Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
              type: string
            metadata:
              type: object
            spec:
              description: PolicySpec is the spec of the Policy resource. The spec includes multiple fields, where each field represents a different policy. Only one policy (field) is allowed.
              type: object
              properties:
                accessControl:
                  description: AccessControl defines an access policy based on the source IP of a request.
                  type: object
                  properties:
                    allow:
                      type: array
                      items:
                        type: string
                    deny:
                      type: array
                      items:
                        type: string
                egressMTLS:
                  description: EgressMTLS defines an Egress MTLS policy.
                  type: object
                  properties:
                    ciphers:
                      type: string
                    protocols:
                      type: string
                    serverName:
                      type: boolean
                    sessionReuse:
                      type: boolean
                    sslName:
                      type: string
                    tlsSecret:
                      type: string
                    trustedCertSecret:
                      type: string
                    verifyDepth:
                      type: integer
                    verifyServer:
                      type: boolean
                ingressMTLS:
                  description: IngressMTLS defines an Ingress MTLS policy.
                  type: object
                  properties:
                    clientCertSecret:
                      type: string
                    verifyClient:
                      type: string
                    verifyDepth:
                      type: integer
                jwt:
                  description: JWTAuth holds JWT authentication configuration.
                  type: object
                  properties:
                    realm:
                      type: string
                    secret:
                      type: string
                    token:
                      type: string
                rateLimit:
                  description: RateLimit defines a rate limit policy.
                  type: object
                  properties:
                    burst:
                      type: integer
                    delay:
                      type: integer
                    dryRun:
                      type: boolean
                    key:
                      type: string
                    logLevel:
                      type: string
                    noDelay:
                      type: boolean
                    rate:
                      type: string
                    rejectCode:
                      type: integer
                    zoneSize:
                      type: string
      served: true
      storage: false
EOF
  )
}

resource "kubernetes_manifest" "crd_transportservers_nginx" {
    manifest = yamldecode(
<<-EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.11.1
  creationTimestamp: null
  name: transportservers.k8s.nginx.org
spec:
  group: k8s.nginx.org
  names:
    kind: TransportServer
    listKind: TransportServerList
    plural: transportservers
    shortNames:
      - ts
    singular: transportserver
  scope: Namespaced
  versions:
    - additionalPrinterColumns:
        - description: Current state of the TransportServer. If the resource has a valid status, it means it has been validated and accepted by the Ingress Controller.
          jsonPath: .status.state
          name: State
          type: string
        - jsonPath: .status.reason
          name: Reason
          type: string
        - jsonPath: .metadata.creationTimestamp
          name: Age
          type: date
      name: v1alpha1
      schema:
        openAPIV3Schema:
          description: TransportServer defines the TransportServer resource.
          type: object
          properties:
            apiVersion:
              description: 'APIVersion defines the versioned schema of this representation of an object. Servers should convert recognized schemas to the latest internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
              type: string
            kind:
              description: 'Kind is a string value representing the REST resource this object represents. Servers may infer this from the endpoint the client submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
              type: string
            metadata:
              type: object
            spec:
              description: TransportServerSpec is the spec of the TransportServer resource.
              type: object
              properties:
                action:
                  description: Action defines an action.
                  type: object
                  properties:
                    pass:
                      type: string
                host:
                  type: string
                ingressClassName:
                  type: string
                listener:
                  description: TransportServerListener defines a listener for a TransportServer.
                  type: object
                  properties:
                    name:
                      type: string
                    protocol:
                      type: string
                serverSnippets:
                  type: string
                sessionParameters:
                  description: SessionParameters defines session parameters.
                  type: object
                  properties:
                    timeout:
                      type: string
                streamSnippets:
                  type: string
                upstreamParameters:
                  description: UpstreamParameters defines parameters for an upstream.
                  type: object
                  properties:
                    connectTimeout:
                      type: string
                    nextUpstream:
                      type: boolean
                    nextUpstreamTimeout:
                      type: string
                    nextUpstreamTries:
                      type: integer
                    udpRequests:
                      type: integer
                    udpResponses:
                      type: integer
                upstreams:
                  type: array
                  items:
                    description: Upstream defines an upstream.
                    type: object
                    properties:
                      failTimeout:
                        type: string
                      healthCheck:
                        description: HealthCheck defines the parameters for active Upstream HealthChecks.
                        type: object
                        properties:
                          enable:
                            type: boolean
                          fails:
                            type: integer
                          interval:
                            type: string
                          jitter:
                            type: string
                          match:
                            description: Match defines the parameters of a custom health check.
                            type: object
                            properties:
                              expect:
                                type: string
                              send:
                                type: string
                          passes:
                            type: integer
                          port:
                            type: integer
                          timeout:
                            type: string
                      loadBalancingMethod:
                        type: string
                      maxConns:
                        type: integer
                      maxFails:
                        type: integer
                      name:
                        type: string
                      port:
                        type: integer
                      service:
                        type: string
            status:
              description: TransportServerStatus defines the status for the TransportServer resource.
              type: object
              properties:
                message:
                  type: string
                reason:
                  type: string
                state:
                  type: string
      served: true
      storage: true
      subresources:
        status: {}
EOF
    )
}

resource "kubernetes_manifest" "dockerconfigjson_nginx" {
  manifest = yamldecode(
<<-EOF
apiVersion: v1
data:
  .dockerconfigjson: eyJhdXRocyI6eyI5NzQ5Nzk2MDIyMTEuZGtyLmVjci51cy1lYXN0LTEuYW1hem9uYXdzLmNvbSI6eyJ1c2VybmFtZSI6IkFXUyIsInBhc3N3b3JkIjoiZXlKd1lYbHNiMkZrSWpvaU0weHpVVGRwUkV0RVkyaG9LM1ppYzNwRVNVSlNTSFYwWlUxdllWWlhVWGxVVW04MVVVUXZPWFV2Y3l0S1dXRk1LMFZFTW1wblIxSjBTazFwUzJaamVUUnZabWd4VnpGMFJsbDRjVGhNYldabFN6ZEhOekpYU0RWdVRYaFpUamt2UWxoSGFVTnhVSEZ5ZEUxa2MwbHlOakl4Tmt4UFFYazBiR0pTVkcxd1JVNVBLM0ZJTmxwWFVtMDBUaXRHWm0xWk5uWlJSM2tyYzFrNVJHNTFTVkUwZGxSbU1EbFlZM3BLWXpKTFkxQXJRakZFU25wVlpXWjBhRnBpWmt4d1ZFMU9jVUY2U1dwdE9WZ3hjakZEV2xGT1MzcDNRbEJaVjFkTFkwMXhUV1JHVFVaVWJHaFFXVWt6YWpoMmFXRnVUblZDWXpCVGRrSmpNMWxWVkRobWFYRkVWM0Y2TjJ3MU4weFlUVmhUV0hOUWMzcG1aRWd2ZGxOUU4xWXJMM0ZWTW0wMGRXRllNa1ZQUlc5WE1YaE9WMEZRZFZVd1RETm5kMFZ6VG1wNk0xQTJNbTVNZUdSbVFVZEpWR3B2YzJaSVpEZGxkRWwxZUN0UE9FVk5Sa2xPYzNKMGQwZE9WVVZSZFRJd2MzUkpjamMwZGxsd1pFMTNkVmhWUmtaeGVrRXhLM0JyYUU0MU5HazFNSGhMVDJKUVJVRjNTbWRIV2l0aGVtODRkMk5wU25kVlpGUnpUMVJIVTJ4WlRHZ3dVMVpsYkRsbmFUY3llVWRGUW5CMVpVUkdSVmQxTjFoMGFFZEdOMnh2TnpkT09HVkRNa0l4VVRjemJtZFZZbkJTTUZWcEsxaEhaWFpWY1hCQlZUQlpNMGhHYUZWTlpHNVBiR3BPVjBWeFVsZEplRWMyZGxGQ2NWZHlPVkJVU0hCYVNITnVaVkZhY1U1NlJ6ZHBWM2hOVDJaUmNWaE5UbU5RWnpsSk5XWnZTMHMzTmt4bE9USkJaRE5STUhZM1pIbDZZa3ByY1hRMVpHdEhRelJwUjJ0YVIzbFNVMHhrTVRGQ05UQmxUVWsyWVc1aVRUWTBhVEIxVUVoR2VXNXNhWGcwYlM5WFdYaFVWVTVKUkN0UWJITjJXRFEzTkRKRVZrbGtPVXhoSzFRemFEaHljV0Z3YnpKdmRWcFFOWEo0Tlc1dVZtUmxlVk5PY1dSNGEzVTBVekZNUTFKck5ubzFiRXN4YW10TmNtSk5kVnB0YlRobU9IRTNRM0pvZUZaa2NVdENLMDE0TkhwWVZVUXhNUzgwTkZGbk9ETmxSREJpVGsxMU0wRktiSFIzUVZSV1MwdFhWa3hqY1RVMmRWQldabmxoWkZaMEt5OXVhVmhwVlhCdUsyTTFWVzV3VEZWSVdHVnBlbkk0UWxOdWNVOHllbTE2TVdkelJEVmxiVmw0Ym14TWNtMHZiR1F4TmxwcE5VTnZNamg0T1hVNE9VWllkVWQwUkZSaGNURjViRWw0YWpoWEwzRlBhWGh2VUd4VFRHOVBTMFY1V2xwUVlXUjFjVlJWVUZoU2EwRkNNV0ZvY2pkaEwwMTJkbm8wZDFwemIyVm9NRGxNZFdsUFYyUk9kMVY0YW5abE5URmxPRXhvVEdWMlFYVktRMVpzUjBzNVJHMXRNM0pJVjFadU1taExkRFJzUlhSRWFsRk9kVEJzU0VseVVreE1VSFZGUkcxSmRuWlplbGxtWmtGTE1qZEdTbkZzSzNsQlNucE5hamhuYTA1TmRHNHdUV2hMWTJ4a1RWTllVbTVCZGxaRFJGUnNiazVOVkZSVU1tVTNOemxMTkcxRFUxRjROVTlsUjJaTFVFWjVSVmxoUVQwOUlpd2laR0YwWVd0bGVTSTZJa0ZSUlVKQlNHaDNiVEJaWVVsVFNtVlNkRXB0Tlc0eFJ6WjFjV1ZsYTFoMWIxaFlVR1UxVlVaalpUbFNjVGd2TVRSM1FVRkJTRFIzWmtGWlNrdHZXa2xvZG1OT1FWRmpSMjlIT0hkaVVVbENRVVJDYjBKbmEzRm9hMmxIT1hjd1FrSjNSWGRJWjFsS1dVbGFTVUZYVlVSQ1FVVjFUVUpGUlVSR1VUZGpNVTFYYm5KSVNqSkVkMlJMZDBsQ1JVbEJOek50WlZwVE1uVXpNRTVWTTA1WVZ6WlpRMU5zTmtkQlFrMHdaMGRSU0dwTFJTc3ZaRUp0ZFdaRWNYVkpia2RzV1d0VmFsQndSMXBFV1hoeU9ERktZV0Z6TDJ0dVZVTTFOVUZyUmpZclZGazlJaXdpZG1WeWMybHZiaUk2SWpJaUxDSjBlWEJsSWpvaVJFRlVRVjlMUlZraUxDSmxlSEJwY21GMGFXOXVJam94TmpVM09EVTVNVGMxZlE9PSIsImF1dGgiOiJRVmRUT21WNVNuZFpXR3h6WWpKR2EwbHFiMmxOTUhoNlZWUmtjRkpGZEVWWk1taHZTek5hYVdNemNFVlRWVXBUVTBoV01GcFZNWFpaVmxwWVZWaHNWVlZ0T0RGVlZWRjJUMWhWZG1ONWRFdFhWMFpOU3pCV1JVMXRjRzVTTVVvd1Uyc3hjRk15V21wbFZGSjJXbTFuZUZaNlJqQlNiR3cwWTFSb1RXSlhXbXhUZW1SSVRucEtXRk5FVm5WVVdHaGFWR3ByZGxGc2FFaGhWVTU0VlVoR2VXUkZNV3RqTUd4NVRtcEplRTVyZUZCUldHc3dZa2RLVTFaSE1YZFNWVFZRU3pOR1NVNXNjRmhWYlRBd1ZHbDBSMXB0TVZwT2JscFNVak5yY21NeGF6VlNSelV4VTFaRk1HUnNVbTFOUkd4WldUTndTMWw2U2t4Wk1VRnlVV3BHUlZOdWNGWmFWMW93WVVad2FWcHJlSGRXUlRGUFkxVkdObE5YY0hSUFZtZDRZMnBHUkZkc1JrOVRNM0F6VVd4Q1dsWXhaRXhaTURGNFZGZFNSMVJWV2xWaVIyaFJWMVZyZW1GcWFESmhWMFoxVkc1V1ExbDZRbFJrYTBwcVRURnNWbFpFYUcxaFdFWkZWak5HTms0eWR6Rk9NSGhaVkZab1ZGZElUbEZqTTNCdFdrVm5kbVJzVGxGT01WbHlURE5HVmsxdE1EQmtWMFpaVFd0V1VGSlhPVmhOV0doUFZqQkdVV1JXVlhkVVJFNXVaREJXZWxSdGNEWk5NVUV5VFcwMVRXVkhVbTFSVldSS1ZrZHdkbU15V2tsYVJHUnNaRVZzTVdWRGRGQlBSVlpPVW10c1QyTXpTakJrTUdSUFZsVldVbVJVU1hkak0xSktZMnBqTUdSc2JIZGFSVEV6WkZab1ZsSnJXbmhsYTBWNFN6TkNjbUZGTkRGT1Iyc3hUVWhvVEZReVNsRlNWVVl6VTIxa1NGZHBkR2hsYlRnMFpESk9jRk51WkZaYVJsSjZWREZTU0ZVeWVGcFVSMmQzVlRGYWJHSkViRzVoVkdONVpWVmtSbEZ1UWpGYVZWSkhVbFprTVU0eGFEQmhSV1JIVGpKNGRrNTZaRTlQUjFaRVRXdEplRlZVWTNwaWJXUldXVzVDVTAxR1ZuQkxNV2hJV2xoYVZtTllRa0pXVkVKYVRUQm9SMkZHVms1YVJ6VlFZa2R3VDFZd1ZuaFZiR1JLWlVWak1tUnNSa05qVm1SNVQxWkNWVk5JUW1GVFNFNTFXbFpHWVdOVk5UWlNlbVJ3VmpOb1RsUXlXbEpqVm1oT1ZHMU9VVnA2YkVwT1YxcDJVekJ6TTA1cmVHeFBWRXBDV2tST1VrMUlXVE5hU0d3MldXdHdjbU5ZVVRGYVIzUklVWHBTY0ZJeWRHRlNNMnhUVlRCNGEwMVVSa05PVkVKc1ZGVnJNbGxYTldsVVZGa3dZVlJDTVZWRmFFZGxWelZ6WVZobk1HSlRPVmhYV0doVlZsVTFTbEpEZEZGaVNFNHlWMFJSTTA1RVNrVldhMnhyVDFWNGFFc3hVWHBoUkdoNVkxZEdkMko2U25aa1ZuQlJUbGhLTkU1WE5YVldiVkpzWlZaT1QyTlhValJoTTFVd1ZYcEdUVkV4U25KT2JtOHhZa1Z6ZUdGdGRFNWpiVXBPWkZad2RHSlVhRzFQU0VVelVUTktiMlZHV210alZYUkRTekF4TkU1SWNGbFdWVkY0VFZNNE1FNUdSbTVQUkU1c1VrUkNhVlJyTVRGTk1FWkxZa2hTTTFGV1VsZFRNSFJZVm10NGFtTlVWVEprVmtKWFdtNXNhRnBHV2pCTGVUbDFZVlpvY0ZaWVFuVkxNazB4VmxjMWQxUkdWa2xYUjFad1pXNUpORkZzVG5WalZUaDVaVzB4TmsxWFpIcFNSRlpzWWxac05HSnRlRTFqYlRCMllrZFJlRTVzY0hCT1ZVNTJUV3BvTkU5WVZUUlBWVnBaWkZWa01GSkdVbWhqVkVZMVlrVnNOR0ZxYUZoTU0wWlFZVmhvZGxWSGVGUlVSemxRVXpCV05WZHNjRkZaVjFJeFkxWlNWbFZHYUZOaE1FWkRUVmRHYjJOcVpHaE1NREV5Wkc1dk1HUXhjSHBpTWxadlRVUnNUV1JYYkZCV01sSlBaREZXTkdGdVdteE9WRVpzVDBWNGIxUkhWakpSV0ZaTFVURmFjMUl3Y3pWU1J6RjBUVE5LU1ZZeFduVk5iV2hNWkVSU2MxSllVa1ZoYkVaUFpGUkNjMU5GYkhsVmEzaE5WVWhXUmxKSE1VcGtibHBhWld4c2JWcHJSa3hOYW1SSFUyNUdjMHN6YkVKVGJuQk9ZV3BvYm1Fd05VNWtSelIzVkZkb1RGa3llR3RVVms1WlZXMDFRbVJzV2tSU1JsSnpZbXMxVGxaR1VsVk5iVlV6VG5wc1RFNUhNVVJWTVVZMFRsVTViRkl5V2t4VlJWbzFVbFpzYUZGVU1EbEphWGRwV2tkR01GbFhkR3hsVTBrMlNXdEdVbEpWU2tKVFIyZ3pZbFJDV2xsVmJGUlRiVlpUWkVWd2RFNVhOSGhTZWxveFkxZFdiR0V4YURGaU1XaFpWVWRWTVZaVldtcGFWR3hUWTFSbmRrMVVVak5SVlVaQ1UwUlNNMXByUmxwVGEzUjJWMnRzYjJSdFRrOVJWa1pxVWpJNVNFOUlaR2xWVld4RFVWVlNRMkl3U201aE0wWnZZVEpzU0U5WVkzZFJhMG96VWxoa1NWb3hiRXRYVld4aFUxVkdXRlpWVWtOUlZWWXhWRlZLUmxKVlVrZFZWR1JxVFZVeFdHSnVTa2xUYWtwRlpESlNUR1F3YkVOU1ZXeENUbnBPZEZwV2NGUk5ibFY2VFVVMVZrMHdOVmxXZWxwYVVURk9jMDVyWkVKUmF6QjNXakJrVWxOSGNFeFNVM04yV2tWS2RHUlhXa1ZqV0ZaS1ltdGtjMWRYZEZaaGJFSjNVakZ3UlZkWWFIbFBSRVpMV1ZkR2Vrd3lkSFZXVlUweFRsVkdjbEpxV1hKV1JtczVTV2wzYVdSdFZubGpNbXgyWW1sSk5rbHFTV2xNUTBvd1pWaENiRWxxYjJsU1JVWlZVVlk1VEZKV2EybE1RMHBzWlVoQ2NHTnRSakJoVnpsMVNXcHZlRTVxVlROUFJGVTFUVlJqTVdaUlBUMD0ifX19
kind: Secret
metadata:
  name: repo-secret
  namespace: ${var.nginx_ns}
type: kubernetes.io/dockerconfigjson
EOF
  )
}

resource "kubernetes_daemon_set_v1" "daemon_set_nginx" {
  metadata {
    name      = var.nginx_ns
    namespace = kubernetes_namespace_v1.namespace_nginx.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        app = var.nginx_ns
      }
    }

    template {
      metadata {
        labels = {
          app = var.nginx_ns
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.serviceaccount_nginx.metadata[0].name
        image_pull_secrets {
          name = "repo-secret"
        }
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "eks.amazonaws.com/nodegroup"
                  operator = "In"
                  values   = [var.env]
                }
              }
            }
          }
        }
        container {
          image             = "974979602211.dkr.ecr.us-east-1.amazonaws.com/nginx-ic:3.0.1"
          name              = "nginx-plus-ingress"
          image_pull_policy = "Always"
          port {
            container_port = 80
            host_port      = 80
            name           = "http"
          }
          port {
            container_port = 443
            host_port      = 443
            name           = "https"
          }
          port {
            container_port = 8081
            name           = "readiness-port"
          }
          readiness_probe {
            http_get {
              path = "/nginx-ready"
              port = "readiness-port"
            }
            period_seconds = 1
          }
          security_context {
            allow_privilege_escalation = true
            run_as_user                = 101
            capabilities {
              drop = ["ALL"]
              add  = ["NET_BIND_SERVICE"]
            }
          }
          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          args = [
            "-nginx-plus",
            "-nginx-configmaps=$(POD_NAMESPACE)/nginx-config",
            "-default-server-tls-secret=$(POD_NAMESPACE)/default-server-secret",
            "-nginx-status-allow-cidrs=0.0.0.0/0",
            "enable-snippets"
          ]
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "service_nginx" {
  metadata {
    name = var.nginx_ns
    namespace = kubernetes_namespace_v1.namespace_nginx.metadata[0].name
    annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "http"
        "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol" = "*"
        "service.beta.kubernetes.io/aws-load-balancer-ssl-cert" = aws_acm_certificate.cert.arn
        "service.beta.kubernetes.io/aws-load-balancer-ssl-ports" = "443"
        "service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy" = "ELBSecurityPolicy-TLS13-1-3-2021-06"
        "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags" = "Environment=${var.env}"
    }
  }
  spec {
    selector = {
      app = var.nginx_ns
    }
    port {
      port        = 443
      target_port = 80
      protocol = "TCP"
      name = "https"
    }

    type = "LoadBalancer"
  }
}