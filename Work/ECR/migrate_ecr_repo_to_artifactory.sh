#!/bin/bash
AWS_ACCOUNT_ID="584878871707"
AWS_REGION="us-west-2"
ECR_REPOSITORY="accounting/account-portal/accportalfrontend"
ARTIFACTORY_INSTANCE="artifactory.prod.hulu.com"
ARTIFACTORY_REPO="nexus-releases"


COUNT=0
MAX_COUNT=5
ARTIFACTORY_URL=${ARTIFACTORY_INSTANCE}/${ARTIFACTORY_REPO}
AWS_URL=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

for tag in $(aws ecr describe-images --registry-id ${AWS_ACCOUNT_ID} \
    --repository-name ${ECR_REPOSITORY} \
    --query 'sort_by(imageDetails,& imagePushedAt)[*]' \
    --filter tagStatus=TAGGED --output text --region ${AWS_REGION} \
    | grep IMAGETAGS | awk '{print $2}'); do 
    docker pull ${AWS_URL}/${ECR_REPOSITORY}:${tag}
    docker tag ${AWS_URL}/${ECR_REPOSITORY}:${tag} ${ARTIFACTORY_URL}:${tag}
    docker push ${ARTIFACTORY_URL}:${tag}
    # clear docker images to avoid using all space on agent.
    if [ ${COUNT} -eq ${MAX_COUNT} ]
    then
        docker image prune -a -f
        ((COUNT=0))
    fi
    ((COUNT++))
done