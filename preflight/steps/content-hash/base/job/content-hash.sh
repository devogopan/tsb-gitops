#!/bin/bash
# Exit immediately for non-zero status
set -e
# Check unset variables
set -u

istio_resource_types=(
  "gateways.networking.istio.io"
  "virtualservices.networking.istio.io"
  "envoyfilters.networking.istio.io"
  "destinationrules.networking.istio.io"
  "sidecars.networking.istio.io"
  "authorizationpolicies.security.istio.io"
  "peerauthentications.security.istio.io"
  "requestauthentications.security.istio.io"
  "wasmplugins.extensions.istio.io"
  "workloadentries.networking.istio.io"
  "serviceentries.networking.istio.io"
)
xcp_resource_types=(
  "egressgateways.gateway.xcp.tetrate.io"
  "gateways.gateway.xcp.tetrate.io"
  "gatewaygroups.gateway.xcp.tetrate.io"
  "ingressgateways.gateway.xcp.tetrate.io"
  "istiointernalgroups.istiointernal.xcp.tetrate.io"
  "securitygroups.security.xcp.tetrate.io"
  "securitysettings.security.xcp.tetrate.io"
  "serviceroutes.traffic.xcp.tetrate.io"
  "servicesecuritysettings.security.xcp.tetrate.io"
  "tier1gateways.gateway.xcp.tetrate.io"
  "trafficgroups.traffic.xcp.tetrate.io"
  "trafficsettings.traffic.xcp.tetrate.io"
  "wasmplugindefinitions.extension.xcp.tetrate.io"
  "workspaces.xcp.tetrate.io"
  "workspacesettings.xcp.tetrate.io"
  "globalsettings.xcp.tetrate.io"
)

DELETE=${DELETE:-"false"}

# Function to delete resources based on annotations and labels
delete_resources() {
    local resource_type=$1
    local namespace=$2
    local log_file=$3
    local xcp_prefix="xcp.tetrate.io"
    local tsb_prefix="tsb.tetrate.io"
    local operator_annotation="xcp.tetrate.io/created-by-installer"
    local content_hash_annotation="xcp.tetrate.io/contentHash"
    local tsb_content_hash_annotation="tsb.tetrate.io/contentHash"

    echo "Checking resource ${resource_type} in namespace ${namespace}"

    # Get the list of resources of the specified type in the given namespace
    resources=$(kubectl get "$resource_type" -n "$namespace" -o json | jq -r '.items[] |
    select(.metadata.annotations | try has("'${content_hash_annotation}'") | not) |
    select(.metadata.annotations | try has("'${tsb_content_hash_annotation}'") | not) |
    select(.metadata.annotations | try has("'${operator_annotation}'") | not) |
    select(
      (.metadata.annotations | try keys[] | startswith("'${xcp_prefix}'")) or
      (.metadata.annotations | try keys[] | startswith("'${tsb_prefix}'")) or
      (.metadata.labels | try keys[] | startswith("'${xcp_prefix}'")) or
      (.metadata.labels | try keys[] | startswith("'${tsb_prefix}'"))
    ) | .metadata.name')

    deduplicated_resources=$(echo "${resources[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    # Iterate through each resource and delete it
    for resource in $deduplicated_resources; do
        kubectl get "${resource_type}" -n "${namespace}" "${resource}" -o yaml >> "$log_file"
        echo "---" >> "$log_file"
        # Uncomment to enable deletion
        # if [ "${DELETE}" == "true" ]; then
        #   kubectl delete "$resource_type" -n "$namespace" "$resource"
        # fi
    done
}

handle_xcp_multicluster() {
  local log_file=$1
  local content_hash_annotation="xcp.tetrate.io/contentHash"

  ses=$(kubectl get serviceentries.networking.istio.io -n "xcp-multicluster" -o json | jq -r '.items[] |
  select(.metadata.annotations | try has("'${content_hash_annotation}'") | not) | .metadata.name')

  for resource in $ses; do
    kubectl get serviceentries.networking.istio.io -n xcp-multicluster "${resource}" -o yaml >> "$log_file"
    echo "---" >> "$log_file"
    # Uncomment to enable deletion
    # if [ "${DELETE}" == "true" ]; then
    #   kubectl delete serviceentries.networking.istio.io -n xcp-multicluster "$resource"
    # fi
  done

  drs=$(kubectl get destinationrules -n "xcp-multicluster" -o json | jq -r '.items[] |
        select(.metadata.annotations | try has("'${content_hash_annotation}'") | not) | .metadata.name')

  for resource in $drs; do
    kubectl get destinationrules.networking.istio.io -n xcp-multicluster "${resource}" -o yaml >> "$log_file"
    echo "---" >> "$log_file"
    # Uncomment to enable deletion
    # if [ "${DELETE}" == "true" ]; then
    #   kubectl delete "$resource_type" -n "$namespace" "$resource"
    # fi
  done
}

# Create a persistent directory for log files
persistent_log_dir="./.cleanup-script-logs"
mkdir -p "$persistent_log_dir"

# Persistent log file to track processed namespaces
persistent_log_file="$persistent_log_dir/processed_namespaces.txt"
touch "$persistent_log_file"

# Iterate over all namespaces in parallel
for namespace in $(kubectl get namespaces -o json | jq -r '.items[].metadata.name'); do
    # Check if the namespace has already been processed
    if grep -qx "$namespace" "$persistent_log_file"; then
        echo "Namespace $namespace has already been processed. Skipping..."
        continue
    fi
    echo "Checking $namespace namespace for content hash inconsistencies..."

    if [ "$namespace" == "tsb" ]; then
        echo "Skipping tsb namespace..."
        continue
    fi
    if [ "$namespace" == "xcp-system" ]; then
        echo "Skipping xcp-system namespace..."
        continue
    fi

    # Unique log file for this namespace
    namespace_log="$persistent_log_dir/tsb-missing-hash-$namespace.log"

    if [ "$namespace" == "xcp-multicluster" ]; then
        handle_xcp_multicluster "$namespace_log"
        echo "$namespace" >> "$persistent_log_file"  # Mark namespace as processed
        continue
    fi

    for resource in "${istio_resource_types[@]}"; do
        resource_log="$persistent_log_dir/tsb-missing-hash-$namespace-$resource.log"
        delete_resources "$resource" "$namespace" "$resource_log" &
    done
    for resource in "${xcp_resource_types[@]}"; do
        resource_log="$persistent_log_dir/tsb-missing-hash-$namespace-$resource.log"
        delete_resources "$resource" "$namespace" "$resource_log" &
    done
    wait

    # Mark namespace as processed after handling all resources
    echo "$namespace" >> "$persistent_log_file"
done

if ls "$persistent_log_dir"/*.log 1> /dev/null 2>&1; then
    # Merge all log files into a single consolidated log file
    cat "$persistent_log_dir"/*.log > tsb-missing-hash.log
else
    echo "No configs with missing content hash detected."
    touch tsb-missing-hash.log
fi
