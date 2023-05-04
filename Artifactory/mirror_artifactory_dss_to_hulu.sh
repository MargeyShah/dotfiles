# This script takes a full repo name (not one ending with -local) and mirrors from DSS -> Hulu. 
# Handles the cases where repo names don't follow convention (teamname-package or teamname-package-local), as an example: cm-docker-dev-tmp
# To batch mirror many repos of the same package type. keep a file with a single repo name per line:
# cat /path/to/repo_list.txt | xargs -I{} ./mirror-docker.sh -r {} -p maven -u ""
# URL Prefixes/package types can be found here: https://jfrog.com/help/r/jfrog-artifactory-documentation/smart-remote-repositories
# Call it with ./mirror.sh -r <repo_name> -p <package_type> -u <url_prefix>
while getopts ":r:p:u:" opt; do
  case $opt in
    r)
      REPO_NAME=$OPTARG
      ;;
    p)
      PACKAGE=$OPTARG
      ;;
    u)
      URL_PREFIX=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

echo "If URL_PREFIX is empty, make sure to remove the following / after URL_PREFIX on both lines below"
echo "URL PREFIX is $URL_PREFIX \nREPO NAME is $REPO_NAME\nPACKAGE TYPE is $PACKAGE\nPress enter to continue..."
read

frogger repo create-remote --smart --url https://artifactory.us-east-1.bamgrid.net/artifactory/${URL_PREFIX}/${REPO_NAME}-local \
    --package-type ${PACKAGE} --target-urls https://artifactory.ava.prod.hulu.com ${REPO_NAME}-local
 
frogger repo create-virtual --package-type ${PACKAGE} --add-repos ${REPO_NAME}-local  \
    --target-urls https://artifactory.ava.prod.hulu.com ${REPO_NAME}
 
frogger repo create-remote --smart --url https://artifactory.ava.prod.hulu.com/artifactory/${URL_PREFIX}/${REPO_NAME}-local --package-type ${PACKAGE} \
    --target-urls https://artifactory.aor.prod.hulu.com ${REPO_NAME}-local
 
frogger repo create-virtual --package-type ${PACKAGE} --add-repos ${REPO_NAME}-local  \
    --target-urls https://artifactory.aor.prod.hulu.com ${REPO_NAME}
