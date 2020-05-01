#!/bin/bash

POD_NAME="kv-test-$(uuidgen | head -c 8)"
VOLUME_NAME="secrets-store-inline"
MOUNT_PATH="/mnt/secrets-store"
SECRET_ALIAS="demo_alias"

az aks get-credentials -g $rg_name -n $aks_cluster_name --overwrite-existing

# Deploy test pod
read -r -d '' KV_POD_YAML << EOM
kind: Pod
apiVersion: v1
metadata:
  name: $POD_NAME
  labels:
    aadpodidbinding: "$aad_pod_id_binding_selector"
spec:
  containers:
    - name: $POD_NAME
      image: nginx
      volumeMounts:
      - name: $VOLUME_NAME
        mountPath: "$MOUNT_PATH"
        readOnly: true
  volumes:
    - name: $VOLUME_NAME
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          providerName: "azure"
          usePodIdentity: "true"
          tenantId: "$tenant_id"
          keyvaultName: "$key_vault_name"
          objects: |
            array:
              - |
                objectName: "$SECRET_NAME"
                objectAlias: "$SECRET_ALIAS"
                objectType: secret
EOM

if ! echo "$KV_POD_YAML" | kubectl apply -f -
then
    echo "Unable to deploy test pod into the cluster."
    exit 1
fi

kubectl wait --for=condition=Ready --timeout=120s pod/$POD_NAME
kubectl describe pod/$POD_NAME
kubectl exec -i $POD_NAME ls $MOUNT_PATH

ACTUAL_VALUE=$(kubectl exec -i $POD_NAME cat $MOUNT_PATH/$SECRET_ALIAS)

kubectl delete pod $POD_NAME

if [ "$SECRET_VALUE" == "$ACTUAL_VALUE" ]; then
    echo "AKS - Key Vault test passed"
else
    echo "AKS - Key Vault test failed"
    exit 1
fi
