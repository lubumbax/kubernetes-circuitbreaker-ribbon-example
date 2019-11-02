#FROM openjdk:11-alpine
#FROM gcr.io/distroless/java:11
FROM openjdk:8-jdk-slim
VOLUME /tmp
ARG JAR_FILE=target/name-service-0.0.1-SNAPSHOT.jar
COPY ${JAR_FILE} app.jar
ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-jar","/app.jar"]
