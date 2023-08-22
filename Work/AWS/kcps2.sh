devx login
devx mariner kubeconfig
kubectl config use-context ps2-prod-br-us-east-1
namespaces=$(kubectl get namespaces | grep jenkins-central | awk NF=1 )
for val in $namespaces
do
        echo $val
        kubectl get pods -n $val 
done
