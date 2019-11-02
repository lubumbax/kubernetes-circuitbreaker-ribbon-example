
This example is based on the code at [Kubernetes Circuit Breaker & Load Balancer Example](https://github.com/spring-cloud/spring-cloud-kubernetes/tree/master/spring-cloud-kubernetes-examples/kubernetes-circuitbreaker-ribbon-example)
I am using the code from that repository to test Ribbon and Hystrix circuit breaker in Spring Cloud Kubernetes.

Here are some changes that I am introducing:
- removed the dependence to the parent pom files 
- added my own deploy script/files for deploying to my local Minikube
- remedy to Hystrix failover on the first request 

### Run the example
Deploy the example with:
```shell script
./deploy -v local
```

Observe the endpoints available for each service:
```shell script
$ kubectl -n examples get endpoints
```
There should be two for the `name` service:
```
NAME       ENDPOINTS                           AGE
greeting   172.17.0.18:8101                    2m
name       172.17.0.15:8102,172.17.0.16:8102   2m1s
```

Get the IP address of your K8s cluster:
```shell script
$ kubectl cluster-info
```
The output should be something like this:
```
Kubernetes master is running at https://192.168.64.8:8443
KubeDNS is running at https://192.168.64.8:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

Reach the greeting service:
```shell script
$ curl http://192.168.64.8:30301/greeting ; echo ""
```

## Troubleshooting

```shell script
$ kubectl -n examples logs -l app=greeting-service -f
$ kubectl -n examples logs -l app=name-service -f
```

### Solution to Circuit Breaker trip on first call

The first call to the Hystrix command `NameService.getName()` trips the circuit breaker resulting in the the fallback method being called.
(TODO: add some logs)
(TODO: explain why)
Further calls will already work.
I found that I am not the first one.
(TODO: add some references). 

As a solution, I suggest to make the same call to one of the pods of the remote service directly from the fallback method.
For that, we can use `DiscoveryClient` to retrieve the IP address and port of one of the remote pods and calling it directly with a brand new `RestTemplate` (instead of using the _load-balanced_ one)  

```java
@HystrixCommand(
    fallbackMethod = "getNameFallback",
    commandProperties = {
        @HystrixProperty(name = "execution.isolation.thread.timeoutInMilliseconds", value = "1000")
    }
)
public String getName(int delay) {
    return this.restTemplate.getForObject(String.format("http://%s/name?delay=%d", SERVICE_ID, delay), String.class);
}

private String getNameFallback(int delay) {
    log.warn("Running the fallback version");
    RestTemplate rt = new RestTemplate();
    return rt.getForObject(getUrl(delay), String.class);
}

private String getUrl(int delay) {
    debugDiscoveryClient();
    String url = String.format("http://%s/name?delay=%d", SERVICE_ID, delay);
    if (discoveryClient != null) {
        Optional<ServiceInstance> svc = discoveryClient.getInstances(SERVICE_ID).stream().findFirst();
        if (svc.isPresent()) {
            String host = svc.get().getHost();
            int port = svc.get().getPort();
            url = "http://" + host + ":" + port + "?delay=" + delay;
        }
    }
    return url;
}
```

### Deployment Script

The `deploy.sh` script was implemented to assist with the development process of microservices on a given K8s cluster. 
Read the comments in the script for more details. 
The script is a WIP but can be easily adapted to other projects if needed.

- Configure the `ENVIRONMENTS_REG` variable with the K8s environment(s) where you want to deploy to. For instance:
    ```shell script
    ENVIRONMENTS_REG=( \
      "local|minikube|k8s/env/local|Local K8s Cluster" \
      "test|eks-example-test|k8s/env/test|AWS EKS Test" \
      "prod|eks-example-prod|k8s/env/prod|AWS EKS Production" \
    )
    ```  
    The format of each entry is as follows:
    * `env-name`         id of the environment (we will use it when runing the script, eg `./deploy.sh -v local`)
    * `context-name`     name of the K8s context as retrieved from `kubectl config get-contexts`
    * `env-config-path`  see below
    * `description`      displayable description string
    
    The `env-config-path` element must be a path accessible by this script; there the following subdirectories are expected:
    * `namespaces/`   containing the definition of the namespace where we want to deploy (if different than `default`)
    * `rbac/`         containing the definition of service accounts / roles (all files will be processed)
    * `volumes/`      containing the definition of K8s (persistent) volumes (all files will be processed)
    * `services/`     containing the definition of services/deployments (each file matching `<service-name>-service.yaml>`)
    * `config-maps/`  containing the definition of K8s config maps (each file matching `<service-name>-config.yaml`)

- Configure the `SERVICES_REG` variable with the services implemented in our project:
    ```shell script
    SERVICES_REG=( \
      "name|name-service|Name Service"          \
      "greeting|greeting-service|Greeting Service" \
    )
    ``` 
    Each entry is a service implemented in our project, with the format `service-name|directory-name|description`.
    The `directory-name` must match the directory under which we can find each service.
    
- Configure the `K8S_NAMESPACE` variable

#### Examples
To deploy the whole project to the `local` environment:
```shell script
./deploy.sh -v -c local
```
That recreates the K8s namespace completely.

To deploy it all without recreating the K8s namespace (much faster):
```shell script
./deploy.sh -v local
```
That will create the K8s namespace if it didn't exist. 

To deploy only the 'greeting' service to the `local` environment:
```shell script
./deploy.sh -v -s greeting local
```

To rebuild the Docker image only of the 'greeting' service and deploy it to the `local` environment:
```shell script
./deploy.sh -v -s greeting -D local
```

To rebuild the sources and the Docker image only of the 'greeting' service and deploy it to the `local` environment:
```shell script
./deploy.sh -v -s greeting -B -D local
```

To recreate the namespace rebuilding and deploying all services (-C triggers -B and -D):
```shell script
./deploy.sh -c -C local
```



<!--
## Kubernetes Circuit Breaker & Load Balancer Example

This example demonstrates how to use [Hystrix circuit breaker](https://martinfowler.com/bliki/CircuitBreaker.html) and the [Ribbon Load Balancing](https://microservices.io/patterns/client-side-discovery.html). The circuit breaker which is backed with Ribbon will check regularly if the target service is still alive. If this is not loner the case, then a fall back process will be excuted. In our case, the REST `greeting service` which is calling the `name Service` responsible to generate the response message will reply a "fallback message" to the client if the `name service` is not longer replying.
As the Ribbon Kubernetes client is configured within this example, it will fetch from the Kubernetes API Server, the list of the endpoints available for the name service and loadbalance the request between the IP addresses available

### Running the example

This project example runs on ALL the Kubernetes or OpenShift environments, but for development purposes you can use [Minishift - OpenShift](https://github.com/minishift/minishift) or [Minikube - Kubernetes](https://kubernetes.io/docs/getting-started-guides/minikube/) tool
to install the platform locally within a virtual machine managed by VirtualBox, Xhyve or KVM, with no fuss.

### Build/Deploy using Minikube

First, create a new virtual machine provisioned with Kubernetes on your laptop using the command `minikube start`.

Next, you can compile your project and generate the Kubernetes resources (yaml files containing the definition of the pod, deployment, build, service and route to be created)
like also to deploy the application on Kubernetes in one maven line :

```
mvn clean install fabric8:deploy -Dfabric8.generator.from=fabric8/java-jboss-openjdk8-jdk -Pkubernetes
```

### Call the Greeting service

When maven has finished to compile the code but also to call the platform in order to deploy the yaml files generated and tell to the platform to start the process
to build/deploy the docker image and create the containers where the Spring Boot application will run 'greeting-service" and "name-service", you will be able to 
check if the pods have been created using this command :

```
kc get pods
```

If the status of the Spring Boot pod application is `running` and ready state `1`, then you can
get the external address IP/Hostname to be used to call the service from your laptop

```
minikube service --url greeting-service 
```

and then call the service using the curl client

```
curl https://IP_OR_HOSTNAME/greeting
```

to get a response as such 

```
Hello from name-service-1-0dzb4!d
```

### Verify the load balancing

First, scale the number of pods of the `name service` to 2

```
kc scale --replicas=2 deployment name-service
```

Wait a few minutes before to issue the curl request to call the Greeting Service to let the platform to create the new pod.

```
kc get pods --selector=project=name-service
NAME                            READY     STATUS    RESTARTS   AGE
name-service-1652024859-fsnfw   1/1       Running   0          33s
name-service-1652024859-wrzjs   1/1       Running   0          6m
```

If you issue the curl request to access the greeting service, you should see that the message response
contains a different id end of the message which corresponds to the name of the pod.

```
Hello from name-service-1-0ss0r!
```

As Ribbon will question the Kubernetes API to get, base on the `name-service` name, the list of IP Addresses assigned to the service as endpoints,
you should see that you will get a response from one of the 2 pods running

```
kc get endpoints/name-service
NAME           ENDPOINTS                         AGE
name-service   172.17.0.5:8080,172.17.0.6:8080   40m
```

Here is an example about what you will get

```
curl https://IP_OR_HOSTNAME/greeting
Hello from name-service-1652024859-hf3xv!
curl https://IP_OR_HOSTNAME/greeting
Hello from name-service-1652024859-426kv!
...
```

### Test the fall back

In order to test the circuit breaker and the fallback option, you will scale the `name-service` to 0 pods as such

```
kc scale --replicas=0 deployment name-service
```

and next issue a new curl request to get the response from the greeting service

```
Hello from Fallback!
```
 
### Build/Deploy using Minishift

First, create a new virtual machine provisioned with OpenShift on your laptop using the command `minishift start`.

Next, log on to the OpenShift platform and next within your terminal use the `oc` client to create a project where
we will install the circuit breaker and load balancing application

```
oc new-project circuit-loadbalancing
```

When using OpenShift, you must assign the `view` role to the *default* service account in the current project in orde to allow our Java Kubernetes Api to access
the API Server :

```
oc policy add-role-to-user view --serviceaccount=default
```

You can now compile your project and generate the OpenShift resources (yaml files containing the definition of the pod, deployment, build, service and route to be created)
like also to deploy the application on the OpenShift platform in one maven line :

```
mvn clean install fabric8:deploy -Pkubernetes
```

### Call the Greeting service

When maven has finished to compile the code but also to call the platform in order to deploy the yaml files generated and tell to the platform to start the process
to build/deploy the docker image and create the containers where the Spring Boot application will run 'greeting-service" and "name-service", you will be able to 
check if the pods have been created using this command :

```
oc get pods --selector=project=greeting-service
```

If the status of the Spring Boot pod application is `running` and ready state `1`, then you can
get the external address IP/Hostname to be used to call the service from your laptop

```
oc get route/greeting-service 
```

and then call the service using the curl client

```
curl https://IP_OR_HOSTNAME/greeting
```

to get a response as such 

```
Hello from name-service-1-0dzb4!d
```

### Verify the load balancing

First, scale the number of pods of the `name service` to 2

```
oc scale --replicas=2 dc name-service
```

Wait a few minutes before to issue the curl request to call the Greeting Service to let the platform to create the new pod.

```
oc get pods --selector=project=name-service
NAME                   READY     STATUS    RESTARTS   AGE
name-service-1-0ss0r   1/1       Running   0          3m
name-service-1-fblp1   1/1       Running   0          36m
```

If you issue the curl request to access the greeting service, you should see that the message response
contains a different id end of the message which corresponds to the name of the pod.

```
Hello from name-service-1-0ss0r!
```

As Ribbon will question the Kubernetes API to get, base on the `name-service` name, the list of IP Addresses assigned to the service as endpoints,
you should see that you will get a different response from one of the 2 pods running

```
oc get endpoints/name-service
NAME           ENDPOINTS                         AGE
name-service   172.17.0.2:8080,172.17.0.3:8080   40m
```

Here is an example about what you will get

```
curl https://IP_OR_HOSTNAME/greeting
Hello from name-service-1-0ss0r!
curl https://IP_OR_HOSTNAME/greeting
Hello from name-service-1-fblp1!
...
```

### Test the fall back

In order to test the circuit breaker and the fallback option, you will scale the `name-service` to 0 pods as such

```
oc scale --replicas=0 dc name-service
```

and next issue a new curl request to get the response from the greeting service

```
Hello from Fallback!
```
-->

