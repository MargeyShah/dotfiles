ECR_ACCOUNT_ID="584878871707"
AWS_REGION="us-west-2"
ECR_REPOSITORY="accounting/account-portal/accportalfrontend"
IMAGES="img1,img2,img3"
ARTIFACTORY_INSTANCE="artifactory.prod.hulu.com"
ARTIFACTORY_REPO="nexus-releases"


#!/bin/bash
usage() {
  echo "Missing parameter(s), please try running the job again with all fields filled out."
  exit 1
}
if [ -z "${ECR_REPOSITORY}" ] || [ -z "${ECR_ACCOUNT_ID}" ] || [ -z "${AWS_REGION}" ] ||[ -z "${IMAGES}" ] || [ -z "${ARTIFACTORY_INSTANCE}" ] || [ -z "${ARTIFACTORY_REPO}" ]; then
  usage
fi
COUNT=0
MAX_COUNT=5
IFS=',' read -ra tags <<< "${IMAGES}"
AWS_URL=${ECR_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
ARTIFACTORY_URL=${ARTIFACTORY_INSTANCE}/${ARTIFACTORY_REPO}

for tag in "${tags[@]}"; do
  docker pull ${AWS_URL}/${ECR_REPOSITORY}:${tag}
  docker tag ${AWS_URL}/${ECR_REPOSITORY}:${tag} ${ARTIFACTORY_URL}:${tag}
  docker push ${ARTIFACTORY_URL}:${tag}
  if [ ${COUNT} -eq ${MAX_COUNT} ]
  then
      docker image prune -a -f
      ((COUNT=0))
  fi
  ((COUNT++))
done
