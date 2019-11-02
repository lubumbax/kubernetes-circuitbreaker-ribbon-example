/*
 * HEINEKEN International - eTrade Platform
 *
 * Copyright (c) HEINEKEN International. All rights reserved.
 *
 * This software was developed by Valtech for HEINEKEN International.
 * This software is confidential and proprietary information of
 * HEINEKEN International ("Confidential Information").
 */
package org.springframework.cloud.kubernetes.examples;

import org.springframework.scheduling.annotation.Async;

import java.util.concurrent.CompletableFuture;

public class AsyncInitializer {
	@Async
	public CompletableFuture<Object> run(Runnable r) {
		try {
			r.run();
		} catch (Exception e) {}

		return null;
	}
}
