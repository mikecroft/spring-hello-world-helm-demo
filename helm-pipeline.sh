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
export SECRET_NAME=aws-ecr-pull-secret
export DOCKER_REGISTRY_SERVER=014056181913.dkr.ecr.eu-west-1.amazonaws.com/cmpp-workers
export DOCKER_USER=AWS
# export DOCKER_PASSWORD=$(aws ecr get-login-password --region eu-west-1)
export DOCKER_PASSWORD=changeme

# Project and app properties
export PROJECT=demo-deployment
export RELEASE=demo-release

# To be used to rename the kubecontext. The format here is:
#     namespace/cluster/user
# The actual namespaces for each are ${PROJECT}-dev, ${PROJECT}-test
# etc but if we were doing this "for real" then the namespace would stay
# the same and only the cluster would change.
# Since these are only references to the actual kubecontext, it doesn't
# matter.
export DEV_TARGET=${PROJECT}/dev/$(oc whoami)
export TST_TARGET=${PROJECT}/test/$(oc whoami)
export PRD_TARGET=${PROJECT}/prod/$(oc whoami)
###############################################################################

function init {

    # If we have an argument, override the global ${PROJECT} var
    [[ $1 ]] && local PROJECT=$1
    
    for target in "dev" "test" "prod"
    do
        # If project exists, switch ctx, else create project
        # Create or update secret for pulling from AWS ECR
        if oc project ${PROJECT}-${target} >/dev/null 2>&1 ; then
            printf "    Setting current project to ${PROJECT}-${target}............................Success!\n"
        else
            oc new-project ${PROJECT}-${target}
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

        printf "    Rename kubecontext for ${target}.............................. "
            # Note: this MUST match the structure of the global target variables
            oc config rename-context $(oc config current-context) ${PROJECT}/${target}/$(oc whoami)
        [[ $? -eq 0 ]] && printf "Success!\n" || printf "Fail!\n"
    done
}

function install {

    [[ $1 ]] && target="${PROJECT}/$1/$(oc whoami)"

    # The first argument is the kubecontext
    [[ $1 ]] && kubecontext="--kube-context $target"
    [[ $1 ]] && values="-f helm/spring-hello-world-app/envs/values-$1.yaml"

    helm ${kubecontext} install ${RELEASE} helm/spring-hello-world-app ${values} --wait

}

function chart_test {

    [[ $1 ]] && target="${PROJECT}/$1/$(oc whoami)"

    kubecontext="--kube-context=$target"
    occontext="--context=$target"

    oc ${occontext} delete pod ${RELEASE}-spring-hello-world-app-test-connection
    helm ${kubecontext} test ${RELEASE} --logs

}

function usage {

    echo "
    Script to create a project and install the sample spring-hello-world-app Helm
    chart to it. It takes the name of a project and a \"Release name\". All
    Helm chart installations are known as \"Releases\" and the resulting
    resources will be known as \"\$RELEASE_NAME-\$CHART_NAME\".

    Usage:
        $0 \$PROJECT_NAME \$RELEASE_NAME

    Example:
        # Install the sanmanager chart in \"my-new-project\"
        $0 my-new-project testing-new-feature

    This example will create a chart release in \"my-new-project\" called
    \"testing-new-feature-spring-hello-world-app\"
    "
}


if [ $# -eq 3 ] && [ $3 == "cleanup" ] ; then
    printf "In project $1-dev, "
    helm uninstall -n $1-dev $2
    printf "In project $1-test, "
    helm uninstall -n $1-test $2
    printf "In project $1-prod, "
    helm uninstall -n $1-prod $2
    exit
fi

# Reject uppercase letters in ${RELEASE}
[[ $2 =~ [A-Z] ]] && echo "ERROR: Uppercase letters are not allowed as release names due to DNS specification rules" && exit 1

if [ $# -eq 2 ] ; then
    export PROJECT=$1
    export RELEASE=$2

    export DEV_TARGET=${PROJECT}/dev/$(oc whoami)
    export TST_TARGET=${PROJECT}/test/$(oc whoami)
    export PRD_TARGET=${PROJECT}/prod/$(oc whoami)

    # Initialise 3 projects to simulate 3 clusters
    init ${PROJECT}

    ###############################

    # Install to dev, test, prod

    ###############################
    for TARGET in "dev" "test" "prod"
    do
        printf "    Installing chart in ${TARGET}.............................. "
            install ${TARGET}
        [[ $? -eq 0 ]] && printf "Success!\n" || printf "Fail!\n"


        printf "    Testing chart in ${TARGET}................................. "
            chart_test ${TARGET}
        
        # Did it work?
        if [ $? -eq 0 ] ; then
            printf "Success!\n" 
        else
            printf "Fail!\n\nAborting script\n"
            exit 1
        fi
    done

    echo "    Done!"
    
else
    usage
    exit 1
fi