purple='\033[0;35m'
cyan='\033[0;36m'    
white='\033[0;37m'  
namespaces=$(kubectl get namespaces | grep jenkins-central | awk NF=1 )
for val in $namespaces
do
        echo "${purple}Current pods in ${val} namespace: $cyan"
        kubectl get pods -n $val 
done
