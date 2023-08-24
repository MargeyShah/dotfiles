#!/bin/bash
# Example: 
# ./migrate_ecr_to_artifactory.sh -r accounting/account-portal/accportalfrontend -e 584878871707 -i us-west-2 -t 8feda67a86c3fa6cc84f26fb518085a4abb7c827,snyk-fix-6a4203446dc893a39ef91fc71e714088-8feda67a86c3fa6cc84f26fb518085a4abb7c827 -a nexus-mvn-releases -u artifactory.prod.hulu.com 
usage() {
  echo "Usage: $0 -r <aws_ecr_repository> -e <aws_ecr_account_id> -i <aws_ecr_region> -t <image>,<image2>,.. -a <artifactory_repository> -u <artifactory_url>"
  exit 1
}

while getopts ":r:e:i:t:a:u:" opt; do
  case $opt in
    r) aws_ecr_repository=${OPTARG}
    ;;
    e) aws_ecr_account_id=${OPTARG}
    ;;
    i) aws_ecr_region=${OPTARG}
    ;;
    t) image_tags=${OPTARG}
    ;;
    a) artifactory_repository=${OPTARG}
    ;;
    u) artifactory_url=${OPTARG}
    ;;
    \?) echo "Invalid option -${OPTARG}" >&2
        usage
    ;;
    :) echo "Option -${OPTARG} requires an argument." >&2
        usage
    ;;
  esac
done

if [ -z "${aws_ecr_repository}" ] || [ -z "${aws_ecr_account_id}" ] || [ -z "${aws_ecr_region}" ] ||[ -z "${image_tags}" ] || [ -z "${artifactory_repository}" ] || [ -z "${artifactory_url}" ]; then
  usage
fi
IFS=',' read -ra tags <<< "${image_tags}"

AWS_URL=${aws_ecr_account_id}.dkr.ecr.${aws_ecr_region}.amazonaws.com
aws ecr get-login-password --region ${aws_ecr_region} | docker login --username AWS --password-stdin ${AWS_URL}

for tag in "${tags[@]}"; do
  docker pull ${AWS_URL}/${aws_ecr_repository}:${tag}
  docker tag ${AWS_URL}/${aws_ecr_repository}:${tag} ${artifactory_url}/${artifactory_repository}:${tag}
  # docker push ${artifactory_url}/${artifactory_repository}:${tag}
done
