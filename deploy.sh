#!/bin/bash
# deploy.sh - Deploy to K8s
# murojc@gmail.com

# Default namespace where to deploy K8s elements
K8S_NAMESPACE=examples

# Registry of environments; an array of environments, each one being an array containing the following elements:
# ~ env-name         id of the environment
# ~ context-name     name of the K8s context as retrieved from "kubectl config get-contexts"
# ~ env-config-path  see below
# ~ description      displayable description string for the environment
#
# The 'env-config-path' element must be a path accessible by this script where the following subdirs are expected:
# ~ 'namespaces/'   containing the definition of the namespace where we want to deploy K8s elements
# ~ 'rbac/'         containing the definition of service accounts / roles (all files will be processed)
# ~ 'volumes/'      containing the definition of K8s (persistent) volumes (all files will be processed)
# ~ 'services/'     containing the definition of services/deployments (each file matching <service-name>-service.yaml>)
# ~ 'config-maps/'  containing the definition of K8s config maps (each file matching <service-name>-config.yaml)
ENVIRONMENTS_REG=( \
  "local|minikube|k8s/env/local|Local K8s Cluster" \
  "rel|minikube|k8s/env/rel|AWS EKS Release"       \
  "prod|cluster-tickets-test|k8s/env/prodl|AWS EKS Production" \
)

# Registry of services; an array of services, each service being an array service-name, directory-name, description.
SERVICES_REG=( \
  "name|name-service|Name Service"          \
  "greeting|greeting-service|Greeting Service" \
)

# if 0, errors will be displayed only with the -v option, otherwise display always.
ERROR_ALWAYS=1

# Options defaults
DEF_VERBOSE=0
DEF_VVERBOSE=0
DEF_CLEANK8S=0
DEF_CLEAN=0
DEF_BUILD=0
DEF_DOCKER=0
DEF_SERVICE=""

usage() {
  cat << _EOF

Usage: $0 [-v] [-V] [-h] [-c] [-C] [-B] [-D] [-s <service>] [<environment>}]

Deploys and starts the project to one of the environments

OPTIONS
    -v  Verbose
    -V  Superverbose ('-v' + maven/docker standard output)
    -h  Shows this message.
    -S  Status.
    -c  Clean K8s. In "all services" mode recreates the whole K8s namespace.
    -C  Clean artifacts. Forces -B and -D.
    -B  (re-)Build JARs.
    -D  Build Docker images.
    -s  Process a single service.
_EOF

  if [ ! -z $1 ] ; then
    cat << _EOF

* Service:
  - if '-s service' is not specified, we will be running in "all services" mode. This will process all our implemented services.
  - if '-s service' is specified, we will be running in "single services" mode. This will process only the selected one.

* Environments:
  - Make sure that the environment to deploy is registered (see ENVIRONMENTS_REG at the top of the script)
  - If no environment is specified we will be running our services in "standalone" (aka 'dev') mode (TODO).

* Status:
  - If '-S' is specified it wil just dump the status of our cluster. Any "deploy" action will be skipped.

* Clean:
  - If '-c' (Clean K8s) is activated, in "all services" mode the K8s namespace will be dropped and re-created.
  - If '-C' (Clean Maven) is acivated, it runs 'mvn clean' and forces re-build of the Docker image.
_EOF
  fi
}

OPT_VERBOSE=$DEF_VERBOSE
OPT_VVERBOSE=$DEF_VVERBOSE
OPT_STATUS=0
OPT_CLEANK8S=$DEF_CLEANK8S
OPT_CLEAN=$DEF_CLEAN
OPT_BUILD=$DEF_BUILD
OPT_DOCKER=$DEF_DOCKER
OPT_SERVICE=$DEF_SERVICE

# Get parameters
while getopts "vVhcSCBDs:" opt
do
  case $opt in
    v) OPT_VERBOSE=1 ;;
    V) OPT_VVERBOSE=1 ; OPT_VERBOSE=1 ;;
    h) usage "long" ; exit 0 ;;
    S) OPT_STATUS=1 ;;
    c) OPT_CLEANK8S=1 ;;
    C) OPT_CLEAN=1 ;;
    B) OPT_BUILD=1 ;;
    D) OPT_DOCKER=1 ;;
    m) OPT_SERVICE=$OPTARG ;;
    *) echo "$opt - Unimplemented option." ; usage ; exit 1 ;;
  esac
done
shift $(($OPTIND - 1))

# ---- options validation ----

## Validation - check that a target has been specified (dev/local/prod)
#if [ "$1" == "" ] ; then echo "* ERROR: No target has been specified." ; usage ; exit 1 ; fi
#OPT_TARGET=$1

# Validation - if -c (artifacts clean) we need to force rebuild/re-docker before deploying
if [ $OPT_CLEAN -eq 1 ] ; then
  OPT_BUILD=1
  OPT_DOCKER=1
fi

## Validation - in single-service mode make sure that the directory actually exists
#if [ ! "$OPT_SERVICE" = "" ] && [ ! -d $OPT_SERVICE ] ; then
#  echo "Could not find directory $OPT_SERVICE" ; exit 1 ;
#fi

# Validation - we can't drop the whole K8s namespace in "single-service" mode
if [ $OPT_CLEANK8S -eq 1 ] && [ "$OPT_SERVICE" != "" ] ; then
  echo "* ERROR: We can't drop the whole K8s namespace (-c) in 'single-service' mode (-s)." ; usage ; exit 1 ;
fi

# ---- internal section ----

# Make maven quiet if the option '-V' was not selected
if [ $OPT_VVERBOSE -eq 1 ] ; then
  MVN="mvn"
  DOCKER="docker"
else
  MVN="mvn -q"
  DOCKER="docker --log-level error"
fi

# Prepends a label before each line
# $1 lines
# $2 prepend
function echo_lines {
  echo "$1" | sed -n "s/\(.*\)/$2\1/p"
}

# Runs the command specified and formats standard and error output per '-v'
# If the global variable $ERROR_ALWAYS is 0 standard error is printed per '-v'.
# If the global variable $ERROR_ALWAYS is 1 standard error is printed *always*.
# $1 - command to run
# returns the error code resulting from running the command
function run {
  unset OUTPUT_STD OUTPUT_ERR RET
  eval "$( ($1) 2> >(OUTPUT_ERR=$(cat); typeset -p OUTPUT_ERR) > >(OUTPUT_STD=$(cat); typeset -p OUTPUT_STD); RET=$?; typeset -p RET )"
  if [ $ERROR_ALWAYS -gt 0 ] ; then
    if [ "$OUTPUT_ERR" != "" ] ; then echo_lines "$OUTPUT_ERR" "  #ERROR: " ; fi
  fi
  if [ $OPT_VERBOSE -gt 0 ] ; then
    if [ "$OUTPUT_STD" != "" ] ; then echo_lines "$OUTPUT_STD" "  "; fi
    if [ $ERROR_ALWAYS -eq 0 ] ; then
      if [ "$OUTPUT_ERR" != "" ] ; then echo_lines "$OUTPUT_ERR" "  #ERROR: " ; fi
    fi
  fi
  return $RET
}

# Checks if a given environment exists
# $1 - environment name
# Returns 0 if the environment is found, 1 if not
function environment_find {
  for svc in "${ENVIRONMENTS_REG[@]}" ; do
    E_NAME=$(echo "$svc" | sed -n "s/^\(.*\)|.*|.*|.*$/\1/p" )
    if [ "$E_NAME" == "$1" ] ; then echo "$E_NAME" ; return 0 ; fi
  done
  return 1
}

function environment_get_context_name {
  for svc in "${ENVIRONMENTS_REG[@]}" ; do
    E_NAME=$(echo "$svc" | sed -n "s/^\(.*\)|.*|.*|.*$/\1/p" )
    E_CTX=$(echo "$svc" | sed -n "s/^.*|\(.*\)|.*|.*$/\1/p" )
    if [ "$E_NAME" == "$1" ] ; then echo "$E_CTX" ; return 0 ; fi
  done
  return 1
}

# Retrieves the config-path of a given enviroment from ENVIRONMENTS_REG and sends it to stdout.
# You may want to catch the value in a value at the caller. Eg:
#
#     NAME=$(environment_get_config_path "integration")
#     if [ $? -gt 0 ] ; then echo "Not found" ; fi
#     echo $NAME
#
# $1 - environment name
# Returns 0 if the environment is found, 1 if not
function environment_get_config_path {
  for svc in "${ENVIRONMENTS_REG[@]}" ; do
    E_NAME=$(echo "$svc" | sed -n "s/^\(.*\)|.*|.*|.*$/\1/p" )
    E_PATH=$(echo "$svc" | sed -n "s/^.*|.*|\(.*\)|.*$/\1/p" )
    if [ "$E_NAME" == "$1" ] ; then echo "$E_PATH" ; return 0 ; fi
  done
  return 1
}

function environment_get_description {
  for svc in "${ENVIRONMENTS_REG[@]}" ; do
    E_NAME=$(echo "$svc" | sed -n "s/^\(.*\)|.*|.*|.*$/\1/p" )
    E_DESC=$(echo "$svc" | sed -n "s/^.*|.*|.*|\(.*\)$/\1/p" )
    if [ "$E_NAME" == "$1" ] ; then echo "$E_DESC" ; return 0 ; fi
  done
  return 1
}


# Checks if a given service exists
# $1 - service name
# Returns 0 if the service is found, 1 if not
function service_find {
  for svc in "${SERVICES_REG[@]}" ; do
    S_NAME=$(echo "$svc" | sed -n "s/^\(.*\)|.*|.*$/\1/p" )
    if [ "$S_NAME" == "$1" ] ; then echo "$S_NAME" ; return 0 ; fi
  done
  return 1
}

# Retrieves the directory-name of a given service from SERVICES_REG and sends it to stdout.
# You may want to catch the value in a variable at the caller. Eg:
#
#     DIR=$(service_get_directory "someservice")
#     if [ $? -gt 0 ] ; then echo "Not found" ; fi
#     echo "$DIR"
#
# $1 - service name
# Returns 0 if the service is found, 1 if not
function service_get_directory {
  for svc in "${SERVICES_REG[@]}" ; do
    S_NAME=$(echo "$svc" | sed -n "s/^\(.*\)|.*|.*$/\1/p" )
    S_DIR=$(echo "$svc" | sed -n "s/^.*|\(.*\)|.*$/\1/p" )
    if [ "$S_NAME" == "$1" ] ; then echo "$S_DIR" ; return 0 ; fi
  done
  return 1
}

function service_get_description {
  for svc in "${SERVICES_REG[@]}" ; do
    S_NAME=$(echo "$svc" | sed -n "s/^\(.*\)|.*|.*$/\1/p" )
    S_DESC=$(echo "$svc" | sed -n "s/^.*|.*|\(.*\)$/\1/p" )
    if [ "$S_NAME" == "$1" ] ; then echo "$S_DESC" ; return 0 ; fi
  done
  return 1
}

# $1 - host (or port if only one parameter is passed)
# $2 - port if not indicated then $1 is expected to be the port to be tested on the localhost
# $3 - timeout (milliseconds), defaults to 5000 ms
# Return 0 if success, 1 if error
wait_for_service() {
    if [ -z $1 ] ; then host=localhost ; else host=$1 ; fi
    if [ -z $2 ] ; then
        if [ -z $1 ] ; then return 1 ; else host=localhost && port=$1 ; fi
    else
        port=$2
    fi
    if [ -z $3 ] ; then timeout=5000 ; else timeout=$3 ; fi
    count=0
    while ! nc -z $host $port > /dev/null 2>&1 ; do
        if [ $count -eq $timeout ] ; then return 2 ; else count=$(($count + 1)) ; fi
        sleep 0.001
    done
    return 0
}

# ---- k8s deployment functions ----

show_k8s_status() {
  echo ""
  echo "* Deployments"
  kubectl get deployments --show-labels --namespace $K8S_NAMESPACE
  echo ""
  echo "* Replicasets"
  kubectl get replicasets --show-labels --namespace $K8S_NAMESPACE
  echo ""
  echo "* Pods"
  kubectl get pods --show-labels --namespace $K8S_NAMESPACE
  echo ""
  echo "* Services"
  kubectl get services --show-labels --namespace $K8S_NAMESPACE
  echo ""
}

namespace_delete() {
  kubectl get namespace $K8S_NAMESPACE > /dev/null 2>&1 && ( \
    echo "* Removing namespace" ; \
    run "kubectl delete namespaces $K8S_NAMESPACE"  \
  )

  # todo: browse configured persistent volumes from the configured k8s/env/xx directory for the given environment
  # then iterate each of them checking what "pvc"s they have attached, remove them first and finally remove the "pv".
  kubectl get persistentvolume barcode-pv > /dev/null 2>&1 && ( \
    echo "* Removing persistentvolume examples-pv" ;  \
    run "kubectl delete persistentvolume examples-pv" \
  )
}

# Creates the namespace if it doesn't exist
namespace_create_or_update() {
  # Create the namespace if it doesn't exist
  kubectl get namespace $K8S_NAMESPACE > /dev/null 2>&1 || ( \
    echo "* Creating namespace $K8S_NAMESPACE..." ; \
    run "kubectl apply -f ${E_CPATH}/namespaces/${K8S_NAMESPACE}.yaml" \
  )

  # Apply accounts and volumes always
  echo "* Adding accounts..."
  run "kubectl apply -f ${E_CPATH}/rbac/accounts.yaml"
  echo "* Creating Volumes..."
  run "kubectl apply -f ${E_CPATH}/volumes/examples-pv.yaml"

  # Deploy external services
  #deploy_k8s_mongodb
}



#todo: we want to have two "deploy_k8s" functions, one for our mvn projects and other for not our projects (mongodb, dynamodb, ...)
#deploy_k8s_mvn_service() {
#
#}

# $1 - service name (eg: some), as named in the K8s mainifest
# $2 - package name (eg: some-service), usually matching the directory
# $3 - display name (eg: Some Service)
deploy_k8s_service() {
  S_NAME=$(service_find "$1")
  if [ $? -gt 0 ] ; then echo "* ERROR: The service $1 was not found in the service registry" ; return 1 ; fi

  S_DIR=$(service_get_directory "$1")
  S_DESCR=$(service_get_description "$1")

  if [ $OPT_CLEAN -gt 0 ] ; then
    echo "* Cleaning ${S_DESCR}... "
    pushd . > /dev/null 2>&1 ; cd ${S_DIR}
    run "${MVN} clean"
    if [ $? -ge 1 ] ; then popd > /dev/null 2>&1 ; return 1 ; fi
    popd > /dev/null 2>&1
  fi

  if [ $OPT_BUILD -gt 0 ] ; then
    echo "* Building ${S_DESCR}... "
    pushd . > /dev/null 2>&1 ; cd ${S_DIR}
    run "${MVN} -Dmaven.test.skip=true install"
    if [ $? -ge 1 ] ; then popd > /dev/null 2>&1 ; return 1 ; fi
    popd > /dev/null 2>&1
  fi

  if [ $OPT_DOCKER -gt 0 ] ; then
    echo "* Building ${S_DESCR} Docker image... "
    pushd . > /dev/null 2>&1 ; cd ${S_DIR}
    #run "${MVN} dockerfile:build"
    run "${DOCKER} build -t ${K8S_NAMESPACE}/${S_DIR}:latest ."
    if [ $? -ge 1 ] ; then popd > /dev/null 2>&1 ; return 1 ; fi
    popd > /dev/null 2>&1
  fi

  # If clean k8s the K8s namespace has been dropped already
  if [ ! $OPT_CLEANK8S -eq 1 ] ; then
    echo "* Dropping ${S_DESCR}... "
    run "kubectl delete deployment ${1} --namespace $K8S_NAMESPACE"
    run "kubectl delete service ${1} --namespace $K8S_NAMESPACE"
  fi

  echo "* Deploying ${S_DESCR}... "
  if [ -f ${E_CPATH}/config-maps/"${S_NAME}"-config.yaml ] ; then
    run "kubectl apply -f ${E_CPATH}/config-maps/${S_NAME}-config.yaml"
  fi
  run "kubectl apply -f ${E_CPATH}/services/${S_NAME}-service.yaml"
}

# for now it deploys to the default context; todo: deploy to the context configured for the given environment
deploy_k8s() {
  echo "Deploying to '$E_DESCR' (context '$E_CTX')"
  eval $(minikube docker-env)

  # handle initial k8s stuff (namespace, rbac accounts, ..)
  # dynamodb is also redeployed only if the namespace has been recreated (that way we preserve data)
  if [ $OPT_CLEANK8S -eq 1 ] && [ "$OPT_SERVICE" == "" ] ; then
    kubectl get namespace $K8S_NAMESPACE > /dev/null 2>&1 && namespace_delete
  fi
  namespace_create_or_update

  #todo: add a registry of services that have to be deployed but that we haven't developed (they aren't under Maven)
  #These services are like dependencies for the other services and have to be deployed usually only when the
  #namespace is created. eg:
  #deploy_k8s_mongodb

  if [ "$OPT_SERVICE" == "" ] ; then
    for service in "${SERVICES_REG[@]}" ; do
      S_NAME=$(echo "${service}" | sed -n "s/^\(.*\)|.*|.*$/\1/p" )
      deploy_k8s_service "${S_NAME}"
    done
  else
    deploy_k8s_service "${OPT_SERVICE}"
  fi

  show_k8s_status
}

# ---- main section ----

if [ $OPT_STATUS -eq 1 ] ; then
  show_k8s_status
  exit 0
fi

# If an environment is specified check that it exists in the registry and make its config available globaly
OPT_TARGET=$1
if [ "$OPT_TARGET" == "" ] ; then
  echo "Standalone - TODO"
else
  E_NAME=$(environment_find "$OPT_TARGET")
  if [ $? -gt 0 ] ; then echo "* ERROR: The environment '$OPT_TARGET' was not found in the environments registry" ; exit 1 ; fi

  E_CTX=$(environment_get_context_name "$1")
  E_CPATH=$(environment_get_config_path "$1")
  E_DESCR=$(environment_get_description "$1")

  deploy_k8s
fi

exit 0
