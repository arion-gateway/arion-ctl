#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_DIR="$ROOT/apps/arion_k8s_controller"
REPORT_DIR="${REPORT_DIR:-$APP_DIR/conformance/reports}"

CLUSTER="${CLUSTER:-arion-conformance}"
RUN_NAMESPACE="${RUN_NAMESPACE:-arion-conformance}"
GATEWAY_CLASS="${GATEWAY_CLASS:-arion}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.6.0}"
INFERENCE_EXTENSION_VERSION="${INFERENCE_EXTENSION_VERSION:-v1.5.0}"
GO_IMAGE="${GO_IMAGE:-golang:1.26}"
CONTROLLER_IMAGE="${CONTROLLER_IMAGE:-arion-k8s-controller:conformance}"
ARION_IMAGE="${ARION_IMAGE:-arion-proxy:conformance}"
ARION_PROXY_REPO="${ARION_PROXY_REPO:-$ROOT/../arion}"
CONFORMANCE_ORGANIZATION="${CONFORMANCE_ORGANIZATION:-arion-gateway}"
CONFORMANCE_PROJECT="${CONFORMANCE_PROJECT:-arion}"
CONFORMANCE_URL="${CONFORMANCE_URL:-https://github.com/arion-gateway/arion-ctl}"
CONFORMANCE_VERSION="${CONFORMANCE_VERSION:-dev}"
CONFORMANCE_CONTACT="${CONFORMANCE_CONTACT:-@arion}"

usage() {
  echo "usage: $0 {setup|gateway|inference|all|summary|clean}" >&2
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

using_kind() {
  kubectl config current-context 2>/dev/null | grep -qx "kind-$CLUSTER"
}

ensure_cluster() {
  need kubectl
  need docker
  need kind

  if ! kind get clusters | grep -qx "$CLUSTER"; then
    kind create cluster --name "$CLUSTER"
  fi

  kubectl config use-context "kind-$CLUSTER" >/dev/null
}

build_images() {
  if [ "${BUILD_IMAGES:-true}" = "true" ]; then
    docker build -f "$APP_DIR/Dockerfile" -t "$CONTROLLER_IMAGE" "$ROOT"
    docker build -f "$ARION_PROXY_REPO/docker/Dockerfile" \
      --build-arg "ARION_CARGO_FEATURES=${ARION_CARGO_FEATURES:-}" \
      -t "$ARION_IMAGE" "$ARION_PROXY_REPO"
  else
    docker image inspect "$CONTROLLER_IMAGE" >/dev/null 2>&1 || docker pull "$CONTROLLER_IMAGE"
    docker image inspect "$ARION_IMAGE" >/dev/null 2>&1 || docker pull "$ARION_IMAGE"
  fi

  if using_kind; then
    kind load docker-image "$CONTROLLER_IMAGE" --name "$CLUSTER"
    docker image inspect "$ARION_IMAGE" >/dev/null 2>&1 && \
      kind load docker-image "$ARION_IMAGE" --name "$CLUSTER"
  fi
}

install_crds() {
  kubectl apply -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/$GATEWAY_API_VERSION/standard-install.yaml"
  kubectl apply -k \
    "https://github.com/kubernetes-sigs/gateway-api-inference-extension/config/crd?ref=$INFERENCE_EXTENSION_VERSION"
}

deploy_controller() {
  need helm
  helm upgrade --install arion-ctl "$ROOT/charts/arion-ctl" \
    --namespace arion-system --create-namespace \
    --set-string image.repository="${CONTROLLER_IMAGE%:*}" \
    --set-string image.tag="${CONTROLLER_IMAGE##*:}" \
    --set-string dataPlane.image="$ARION_IMAGE" \
    --set-string gatewayClass.name="$GATEWAY_CLASS" --wait --timeout 5m

  # A rebuilt image keeps its tag, so Helm sees nothing to roll out.
  if [ "${BUILD_IMAGES:-true}" = "true" ]; then
    kubectl -n arion-system rollout restart deployment/arion-ctl-controller
    kubectl -n arion-system rollout status deployment/arion-ctl-controller --timeout=5m
  fi
}

# Namespaces left by an earlier run keep data planes on that run's proxy image.
delete_namespaces() {
  kubectl delete namespace "$@" --ignore-not-found --wait=true
}

setup_runner_rbac() {
  kubectl create namespace "$RUN_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$RUN_NAMESPACE" create serviceaccount conformance-runner \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl create clusterrolebinding conformance-runner-cluster-admin \
    --clusterrole=cluster-admin \
    --serviceaccount="$RUN_NAMESPACE:conformance-runner" \
    --dry-run=client -o yaml | kubectl apply -f -
}

setup() {
  ensure_cluster
  install_crds
  build_images
  deploy_controller
  setup_runner_rbac
  GATEWAY_CLASS="$GATEWAY_CLASS" "$APP_DIR/conformance/smoke.sh"
}

metadata_args() {
  printf ' --organization=%q' "$CONFORMANCE_ORGANIZATION"
  printf ' --project=%q' "$CONFORMANCE_PROJECT"
  printf ' --url=%q' "$CONFORMANCE_URL"
  printf ' --version=%q' "$CONFORMANCE_VERSION"
  printf ' --contact=%q' "$CONFORMANCE_CONTACT"
}

run_job() {
  local name="$1"
  local image="$2"
  local script="$3"

  mkdir -p "$REPORT_DIR"
  kubectl -n "$RUN_NAMESPACE" delete job "$name" --ignore-not-found

  kubectl -n "$RUN_NAMESPACE" apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $name
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: conformance-runner
      containers:
        - name: runner
          image: $image
          command: ["/bin/bash", "-c"]
          args:
            - |
              set +e
              (
$(printf '%s\n' "$script" | sed 's/^/                /')
              ) 2>&1 | tee /reports/$name.log
              result=\${PIPESTATUS[0]}
              printf '%s' "\$result" > /reports/exit-code
              sleep 600
              exit "\$result"
          volumeMounts:
            - name: reports
              mountPath: /reports
      volumes:
        - name: reports
          emptyDir: {}
EOF

  # The previous run's pod keeps the job-name label while it terminates.
  local uid pod result deadline
  uid=$(kubectl -n "$RUN_NAMESPACE" get job "$name" -o jsonpath='{.metadata.uid}')
  deadline=$((SECONDS + 300))
  pod=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    pod=$(kubectl -n "$RUN_NAMESPACE" get pod -l "batch.kubernetes.io/controller-uid=$uid" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
    [ -n "$pod" ] && break
    sleep 2
  done
  [ -n "$pod" ]
  kubectl -n "$RUN_NAMESPACE" wait --for=condition=Ready "pod/$pod" --timeout=5m
  # Longer than the suites' go test -timeout, so a hung suite still reports.
  deadline=$((SECONDS + 7200))
  result=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    result=$(kubectl -n "$RUN_NAMESPACE" exec "$pod" -- cat /reports/exit-code 2>/dev/null) && break
    sleep 5
  done
  # The copied log is complete; kubectl logs returns only the last rotated file.
  kubectl -n "$RUN_NAMESPACE" cp "$pod:/reports/." "$REPORT_DIR"
  cat "$REPORT_DIR/$name.log"
  kubectl -n "$RUN_NAMESPACE" delete job "$name" --wait=false >/dev/null
  [ "$result" = "0" ]

}

gateway() {
  setup_runner_rbac
  delete_namespaces gateway-conformance-infra gateway-conformance-app-backend gateway-conformance-web-backend
  local report="/reports/gateway-api-$GATEWAY_API_VERSION-arion.yaml"
  local meta
  meta="$(metadata_args)"

  run_job "gateway-api-conformance" "$GO_IMAGE" "
set -euo pipefail
git clone --depth 1 --branch '$GATEWAY_API_VERSION' https://github.com/kubernetes-sigs/gateway-api.git /src/gateway-api
cd /src/gateway-api
go test -v -timeout 100m ./conformance -run TestConformance -args \
  --gateway-class='$GATEWAY_CLASS' \
  --supported-features=Gateway,GatewayHTTPListenerIsolation,GatewayInfrastructurePropagation,GatewayPort8080,HTTPRoute,HTTPRoute303RedirectStatusCode,HTTPRoute307RedirectStatusCode,HTTPRoute308RedirectStatusCode,HTTPRouteBackendProtocolH2C,HTTPRouteBackendProtocolWebSocket,HTTPRouteBackendTimeout,HTTPRouteCORS,HTTPRouteMethodMatching,HTTPRouteNamedRouteRule,HTTPRouteParentRefPort,HTTPRoutePathRedirect,HTTPRoutePathRewrite,HTTPRoutePortRedirect,HTTPRouteQueryParamMatching,HTTPRouteRequestTimeout,HTTPRouteResponseHeaderModification,HTTPRouteSchemeRedirect,ReferenceGrant \
  --conformance-profiles=GATEWAY-HTTP \
  --skip-provisional-tests=true \
  --report-output='$report'$meta
"
}

inference() {
  setup_runner_rbac
  delete_namespaces inference-conformance-infra inference-conformance-app-backend
  local report="/reports/inference-extension-$INFERENCE_EXTENSION_VERSION-arion.yaml"
  local meta
  meta="$(metadata_args)"

  # The suite requires the Gateway API CRDs of the gateway-api release it pins, not
  # $GATEWAY_API_VERSION; the flag records their version as UNDEFINED instead of failing.
  run_job "inference-extension-conformance" "$GO_IMAGE" "
set -euo pipefail
git clone --depth 1 --branch '$INFERENCE_EXTENSION_VERSION' https://github.com/kubernetes-sigs/gateway-api-inference-extension.git /src/inference-extension
cd /src/inference-extension/conformance
go test -v -timeout 100m . -args \
  -debug \
  -gateway-class '$GATEWAY_CLASS' \
  -allow-crds-mismatch \
  -cleanup-base-resources=false \
  -report-output='$report'$meta
"
}

summary() {
  local report found=false
  for report in "$REPORT_DIR"/*.yaml; do
    [ -f "$report" ] || continue
    found=true
    echo "== $(basename "$report")"
    grep -E '^  name:|^- (core|extended):|^  (core|extended):|^    result:|Passed:|Failed:|Skipped:|^  summary:' "$report"
  done
  $found || echo "no reports in $REPORT_DIR"
}

# Both suites run even when the first fails; the exit status reports either failure.
all() {
  local status=0
  setup
  gateway || status=1
  inference || status=1
  summary
  return "$status"
}

clean() {
  need kind
  kind delete cluster --name "$CLUSTER"
}

case "${1:-}" in
  setup) setup ;;
  gateway) gateway ;;
  inference) inference ;;
  all) all ;;
  summary) summary ;;
  clean) clean ;;
  *) usage; exit 2 ;;
esac
