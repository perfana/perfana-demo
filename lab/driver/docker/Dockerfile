FROM eclipse-temurin:17-jre
WORKDIR /app
COPY build/libs/lab-driver-0.1.0.jar /app/lab-driver.jar
COPY docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
