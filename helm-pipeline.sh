###############################################################################
#                                                                             #
# A demo pipeline file for deploying a container to OpenShift. This is        #
# (deliberately) simplistic since the eventual pipeline will be written for a #
# proper CI/CD tool, Mockbird. This file should demonstrate some of the       #
# capabilities of OpenShift through the CLI and through applying YAML files.  #
#                                                                             #
###############################################################################

###############################################################################
#                                                                             #
# Set environment variables                                                   #
#                                                                             #
###############################################################################

# Set AWS environment values if not already set.
# obviously we don't commit them to Git

# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
export AWS_DEFAULT_REGION=eu-west-1

# Create Image Pull Secret for AWS ECR registry
# and add to the default service account so images
# can be pulled
export SECRET_NAME=aws-ecr-pull-secret
export DOCKER_REGISTRY_SERVER=014056181913.dkr.ecr.eu-west-1.amazonaws.com/cmpp-workers
export DOCKER_USER=AWS
export DOCKER_PASSWORD=$(aws ecr get-login-password --region eu-west-1)

# Project and app properties
export PROJECT=demo-deployment
export RELEASE=demo-release
export FRIENDLY_NAME=cmpp-sanmanager # Spaces in the name might cause expansion issues
export CONTAINER_IMAGE=014056181913.dkr.ecr.eu-west-1.amazonaws.com/cmpp-workers:sanmanager_uk-rl-53_qb-rc-215-e628983

# ConfigMap properties. Path is for the *pod*, not local
export CONFIG_PATH=/opt/cmpp/application.properties
export CONFIG_FILENAME=application.properties

###############################################################################

function init {
    # If project exists, switch ctx, else create project
    # Create or update secret for pulling from AWS ECR
    if oc project ${PROJECT} >/dev/null 2>&1 ; then
        printf "    Setting current project to ${PROJECT}............................Success!\n"
    else
        oc new-project ${PROJECT}
    fi

    # Make sure secrets are present for pulling images
    printf "    Creating secret to ${SECRET_NAME}.......................... "
    oc delete secret ${SECRET_NAME} >/dev/null 2>&1

    oc create secret docker-registry ${SECRET_NAME} \
        --docker-server=${DOCKER_REGISTRY_SERVER} \
        --docker-username=${DOCKER_USER} \
        --docker-password=${DOCKER_PASSWORD} >/dev/null 2>&1
    [[ $? -eq 0 ]] && printf "Success!\n" || printf "Fail!\n"
    
    printf "    Linking secret ${SECRET_NAME}.............................. "
    oc secrets link default ${SECRET_NAME} \
        --for=pull >/dev/null 2>&1
    [[ $? -eq 0 ]] && printf "Success!\n" || printf "Fail!\n"
}

function install {

    helm install ${RELEASE} helm/cmpp-sanmanager --set imageCredentials.password=${DOCKER_PASSWORD}

}

function usage {

    echo "
    Script to create a project and install the sample cmpp-sanmanager Helm
    chart to it. It takes the name of a project and a \"Release name\". All
    Helm chart installations are known as \"Releases\" and the resulting
    resources will be known as \"\$RELEASE_NAME-\$CHART_NAME\".

    Usage:
        ./$0 \$PROJECT_NAME \$RELEASE_NAME

    Example:
        # Install the sanmanager chart in \"my-new-project\"
        ./$0 my-new-project testing-new-feature

    This example will create a chart release in \"my-new-project\" called
    \"testing-new-feature-cmpp-sanmanager\"
    "
}

if [ $# -ne 2 ] ; then
    usage
else
    export PROJECT=$1
    export RELEASE=$2
    init
    install
    echo "    Done!"
fi