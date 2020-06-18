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
export DOCKER_PASSWORD=$(aws ecr get-login-password --region eu-west-1)

# Project and app properties
export PROJECT=demo-deployment
export RELEASE=demo-release

###############################################################################

function init {

    # If we have an argument, override the global ${PROJECT} var
    [[ $1 ]] && local PROJECT=$1
    
    for target in "dev" "test" "prod"
    do
        # If project exists, switch ctx, else create project
        # Create or update secret for pulling from AWS ECR
        if oc project ${PROJECT}-${target} >/dev/null 2>&1 ; then
            printf "    #    %-79s  #\n" "       Configuring existing project ${PROJECT}-${target}...... "
        else
            printf "    #    %-79s  #\n" "       Creating and configuring project ${PROJECT}-${target}...... "
            oc new-project ${PROJECT}-${target}
        fi

        # Make sure secrets are present for pulling images
        oc delete secret ${SECRET_NAME} >/dev/null 2>&1

        oc create secret docker-registry ${SECRET_NAME} \
            --docker-server=${DOCKER_REGISTRY_SERVER} \
            --docker-username=${DOCKER_USER} \
            --docker-password=${DOCKER_PASSWORD} >/dev/null 2>&1
    
        oc secrets link default ${SECRET_NAME} \
            --for=pull >/dev/null 2>&1

        # Note: this MUST match the structure of the global target variables
        oc config rename-context $(oc config current-context) ${PROJECT}/${target}/$(oc whoami) >/dev/null 2>&1
    done
}

function install {

    helm ${KUBECONTEXT} install ${RELEASE} helm/spring-hello-world-app ${values} --wait  | tr '\n' '\0' | xargs -0 printf "    #           %-70s    #\n"

}

function chart_test {

    oc ${OCCONTEXT} delete pod ${RELEASE}-spring-hello-world-app-test-connection >/dev/null 2>&1
    helm ${KUBECONTEXT} test ${RELEASE} | tr '\n' '\0' | xargs -0 printf "    #           %-70s    #\n"

}

function app_test {

    expected="hello from $1"

    # Get endpoint under test via oc
    endpoint=$(oc ${OCCONTEXT} get route --selector=app.kubernetes.io/instance=${RELEASE} -o=jsonpath='{.items[0].spec.host}')
    
    actual=$(wget -qO- http://${endpoint}/hello)

    printf "    #    %-79s  #\n" "       Expected:    ${expected}"
    printf "    #    %-79s  #\n" "       Actual:      ${actual}"
    printf "    #    %-79s  #\n" " "

    case "$1" in
        dev)
            # Run dev smoke test
            test "${actual}" = "${expected}"
            ;;
        test)
            # Run integration test suite
            test "${actual}" = "${expected}"
            ;;
        prod)
            # Run validation check
            test "${actual}" = "${expected}"
            ;;
        *)
            false
    esac

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

# Block for cleanup. Uninstalls the releases if "cleanup" is given as 3rd arg.
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

    ###############################

    # Initialise 3 projects to simulate 3 clusters

    ###############################

    printf "    #######################################################################################\n"
    printf "    #    %-79s  #\n" " "
    printf "    #    %-79s  #\n" "INFO:  Initialising..."
    printf "    #    %-79s  #\n" " "
    
    init ${PROJECT}

    printf "    #    %-79s  #\n" " "
    printf "    #######################################################################################\n"

    ###############################

    # Install to dev, test, prod

    ###############################

    for CLUSTER in "dev" "test" "prod"
    do
        # To be used to rename the kubecontext. The format here is:
        #     namespace/cluster/user
        # The actual namespaces for each are ${PROJECT}-dev, ${PROJECT}-test
        # etc but if we were doing this "for real" then the namespace would stay
        # the same and only the cluster would change.
        # Since these are only references to the actual kubecontext, it doesn't
        # matter.
        export TARGET="${PROJECT}/${CLUSTER}/$(oc whoami)"
        export KUBECONTEXT="--kube-context ${TARGET}"
        export OCCONTEXT="--context=${TARGET}"
        export VALUES="-f helm/spring-hello-world-app/envs/values-${CLUSTER}.yaml"

        printf "    #######################################################################################\n"
        printf "    #    %-79s  #\n" " "
        printf "    #    %-79s  #\n" "INFO:  Installing chart in ${CLUSTER}..."
        printf "    #    %-79s  #\n" " "
        
            install ${CLUSTER}
        
        printf "    #    %-79s  #\n" " "
        printf "    #    %-79s  #\n" " "
        printf "    #    %-79s  #\n" "INFO:  Validating chart in ${CLUSTER}..."
        printf "    #    %-79s  #\n" " "
            
            chart_test ${CLUSTER}
        
        # Did it work?
        if [ $? -eq 0 ] ; then
            printf "    #    %-79s  #\n" " "
            printf "    #    %-79s  #\n" " "
            printf "    #    %-79s  #\n" "INFO:  Successfully installed!"
            printf "    #    %-79s  #\n" " "
        else
            printf "    #    %-79s  #\n" "ERROR: Failed to install!"
            printf "    #    %-79s  #\n" "       Aborting script"
            printf "    #    %-79s  #\n" " "        
            printf "    #######################################################################################\n"
            exit 1
        fi

        printf "    #    %-79s  #\n" " "
        printf "    #    %-79s  #\n" "INFO:  Testing application in ${CLUSTER}..."
        printf "    #    %-79s  #\n" " "
        
            app_test ${CLUSTER}

        # Did it work?
        if [ $? -eq 0 ] ; then
            printf "    #    %-79s  #\n" " "
            printf "    #    %-79s  #\n" "INFO:  Application test PASSED!"
            printf "    #    %-79s  #\n" " "
            printf "    #######################################################################################\n"
        else
            printf "    #    %-79s  #\n" " "
            printf "    #    %-79s  #\n" "ERROR: Application test FAILED!"
            printf "    #    %-79s  #\n" "       Aborting script"
            printf "    #    %-79s  #\n" " "        
            printf "    #######################################################################################\n"
            exit 1
        fi

    done
    
else
    usage
    exit 1
fi