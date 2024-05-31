kubectl delete namespace argo-p2fs-workflows
kubectl delete namespace argo-p2fs-controller
kubectl delete clusterrole p2fs-argo-workflows-admin
kubectl delete clusterrole p2fs-argo-workflows-controller-cluster-template
kubectl delete clusterrole p2fs-argo-workflows-controller
kubectl delete clusterrole p2fs-argo-workflows-edit
kubectl delete clusterrole p2fs-argo-workflows-server
kubectl delete clusterrole p2fs-argo-workflows-server-cluster-template
kubectl delete clusterrole p2fs-argo-workflows-view
kubectl delete clusterrole extra-read-access-to-argo-p2fs
kubectl delete clusterrolebinding grant-cluster-view-role-to-argo-p2fs
kubectl delete clusterrolebinding grant-extra-read-access-to-argo-p2fs
kubectl delete clusterrolebinding p2fs-argo-gha-workflow-runner-bind
kubectl delete clusterrolebinding p2fs-argo-workflows-controller
kubectl delete clusterrolebinding p2fs-argo-workflows-controller-cluster-template
kubectl delete clusterrolebinding p2fs-argo-workflows-server
kubectl delete clusterrolebinding p2fs-argo-workflows-server-cluster-template

