export APP=spring-hello-world-app
export REG=docker.io/mikecroft

mvn clean package
docker build -t ${APP} .
docker tag ${APP}:latest ${REG}/${APP}:latest
docker push ${REG}/${APP}:latest