/*
 *   Copyright (C) 2016 to the original authors.
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *           https://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */

package org.springframework.cloud.kubernetes.examples;

import com.netflix.hystrix.contrib.javanica.annotation.HystrixCommand;
import com.netflix.hystrix.contrib.javanica.annotation.HystrixProperty;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cloud.client.ServiceInstance;
import org.springframework.cloud.client.discovery.DiscoveryClient;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.List;
import java.util.Optional;

/**
 * Service invoking name-service via REST and guarded by Hystrix.
 *
 * @author Gytis Trikleris
 */
@Slf4j
@Service
public class NameService {

	private static final String SERVICE_ID = "name";

	@Autowired
	private final RestTemplate restTemplate;

	@Autowired
	private DiscoveryClient discoveryClient;

	public NameService(RestTemplate restTemplate) {
		this.restTemplate = restTemplate;
	}

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

	private void debugDiscoveryClient() {
		if (discoveryClient != null) {
			List<String> services = discoveryClient.getServices();
			System.out.println("* List of services: ");
			for (String s : services) {
				System.out.println("  service: " + s);
			}
			System.out.println("* List of 'name' service instances: ");
			for (ServiceInstance si : discoveryClient.getInstances("name")) {
				System.out.println("  host: " + si.getHost() + ", instanceId: " + si.getInstanceId() + ", uri: " + si.getUri() + ", scheme: " + si.getScheme());
			}
		}
	}
}
