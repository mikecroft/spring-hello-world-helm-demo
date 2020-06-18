export APP=spring-hello-world-app
export REG=docker.io/mikecroft

mvn clean package -DskipTests
docker build -t ${APP} .
docker tag ${APP}:latest ${REG}/${APP}:latest
docker push ${REG}/${APP}:latest