#!/usr/bin/env bash
# Requires an installed controller and its GatewayClass. Uses only a fresh namespace.
set -euo pipefail
smoke_namespace="arion-smoke-$(date +%s)-$$"
kubectl create namespace "$smoke_namespace"
trap 'kubectl delete namespace "$smoke_namespace" --wait=false >/dev/null' EXIT
kubectl -n "$smoke_namespace" apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo
spec:
  replicas: 1
  selector:
    matchLabels: {app: echo}
  template:
    metadata:
      labels: {app: echo}
    spec:
      containers:
        - name: echo
          image: hashicorp/http-echo:1.0.0
          args: ['-listen=:8080', '-text=arion-gateway-smoke']
          ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata:
  name: echo
spec:
  selector: {app: echo}
  ports: [{port: 8080, targetPort: 8080}]
---
apiVersion: arion.io/v1alpha1
kind: ArionGatewayParameters
metadata:
  name: smoke
spec:
  serviceType: ClusterIP
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: smoke
spec:
  gatewayClassName: ${GATEWAY_CLASS:-arion}
  infrastructure:
    parametersRef:
      group: arion.io
      kind: ArionGatewayParameters
      name: smoke
  listeners:
    - name: http
      protocol: HTTP
      port: 8080
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: smoke
spec:
  parentRefs: [{name: smoke}]
  rules:
    - backendRefs: [{name: echo, port: 8080}]
YAML
kubectl -n "$smoke_namespace" rollout status deployment/echo --timeout=2m
kubectl -n "$smoke_namespace" wait gateway/smoke --for=condition=Programmed --timeout=3m
service=$(kubectl -n "$smoke_namespace" get services \
  -l gateway.networking.k8s.io/gateway-name=smoke -o jsonpath='{.items[0].metadata.name}')
[ -n "$service" ]
kubectl -n "$smoke_namespace" run check --restart=Never --image=curlimages/curl:8.12.1 \
  --command -- sh -ec "curl --fail --retry 30 --retry-all-errors --retry-delay 2 http://$service:8080/ | grep -qx arion-gateway-smoke"
kubectl -n "$smoke_namespace" wait pod/check --for=jsonpath='{.status.phase}'=Succeeded --timeout=2m
kubectl -n "$smoke_namespace" logs check
printf '%s\n' 'PASS: Gateway API routing through the installed Arion data plane'
