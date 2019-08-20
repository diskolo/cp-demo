  #!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
echo -e "${BLUE}${DIR}${NC}"

#set -o nounset \
#    -o errexit \
#    -o verbose

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "${RED}\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n${NC}"
    exit 1
  fi
}
verify_installed "jq"
verify_installed "docker-compose"
verify_installed "keytool"
verify_installed "mvn"

# Verify Docker memory is increased to at least 8GB
DOCKER_MEMORY=$(docker system info | grep Memory | grep -o "[0-9\.]\+")
if (( $(echo "$DOCKER_MEMORY 7.0" | awk '{print ($1 < $2)}') )); then
  echo -e "${RED}\nWARNING: Did you remember to increase the memory available to Docker to at least 8GB (default is 2GB)? Demo may otherwise not work properly.\n${NC}"
  sleep 3
fi

# Stop existing demo Docker containers
${DIR}/stop.sh
echo -e "${BLUE}$(pwd)${NC}"
# Generate keys and certificates used for SSL
(cd ${DIR}/security && ./certs-create.sh)

# maven compile and add jar to docker-spark/lib which will be the volumen in spark
echo -e "${BLUE}packaging with maven${NC}"
mvn -f ${DIR}/../SentimentAnalysis/pom.xml clean package
echo -e "${BLUE}Copying to docker-spark/lib${NC}"
cp ${DIR}/../SentimentAnalysis/target/SentimentAnalysis-1.0-SNAPSHOT.jar ${DIR}/../docker-spark/lib/

# Bring up Docker Compose
echo -e "${BLUE}Bringing up Docker Compose${NC}"
docker-compose up -d

# Verify Confluent Control Center has started within MAX_WAIT seconds
MAX_WAIT=300
CUR_WAIT=0
echo -e "${BLUE}Waiting up to $MAX_WAIT seconds for Confluent Control Center to start${NC}"
while [[ ! $(docker-compose logs control-center) =~ "Started NetworkTrafficServerConnector" ]]; do
  sleep 3
  CUR_WAIT=$(( CUR_WAIT+3 ))
  if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
    echo -e "${RED}\nERROR: The logs in control-center container do not show 'Started NetworkTrafficServerConnector' after $MAX_WAIT seconds. Please troubleshoot with 'docker-compose ps' and 'docker-compose logs'.\n${NC}"
    exit 1
  fi
done

# Verify Docker containers started
if [[ $(docker-compose ps) =~ "Exit 137" ]]; then
  echo -e "${RED}\nERROR: At least one Docker container did not start properly, see 'docker-compose ps'. Did you remember to increase the memory available to Docker to at least 8GB (default is 2GB)?\n${NC}"
  exit 1
fi


# Verify Docker has the latest cp-kafka-connect image
if [[ $(docker-compose logs connect) =~ "server returned information about unknown correlation ID" ]]; then
  echo -e "\nERROR: Please update the cp-kafka-connect image with 'docker-compose pull'\n"
  exit 1
fi

echo -e "\nRename the cluster in Control Center:"
# If you have 'jq'
curl -X PATCH  -H "Content-Type: application/merge-patch+json" -d '{"displayName":"Kafka Raleigh"}' http://localhost:9021/2.0/clusters/kafka/$(curl -X GET http://localhost:9021/2.0/clusters/kafka/ | jq --raw-output '.[0].clusterId')
# If you don't have 'jq'
#curl -X PATCH  -H "Content-Type: application/merge-patch+json" -d '{"displayName":"Kafka Raleigh"}' http://localhost:9021/2.0/clusters/kafka/$(curl -X GET http://localhost:9021/2.0/clusters/kafka/ | awk -v FS="(clusterId\":\"|\",\"displayName)" '{print $2}' )

# Verify Kafka Connect Worker has started within 120 seconds
MAX_WAIT=120
CUR_WAIT=0
echo "Waiting up to $MAX_WAIT seconds for Kafka Connect Worker to start"
while [[ ! $(docker-compose logs connect) =~ "Herder started" ]]; do
  sleep 3
  CUR_WAIT=$(( CUR_WAIT+3 ))
  if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
    echo -e "\nERROR: The logs in Kafka Connect container do not show 'Herder started'. Please troubleshoot with 'docker-compose ps' and 'docker-compose logs'.\n"
    exit 1
  fi
done

echo -e "\nStart streaming from the twitter source connector:"
chmod 755 ${DIR}/connectors/submit_twitter_source_config.sh
${DIR}/connectors/submit_twitter_source_config.sh

echo -e "\nProvide data mapping to Elasticsearch:"
${DIR}/dashboard/set_elasticsearch_mapping_bot.sh
${DIR}/dashboard/set_elasticsearch_mapping_count.sh

echo -e "\nStart Confluent Replicator:"
${DIR}/connectors/submit_replicator_config.sh

echo -e "\nConfigure Kibana dashboard:"
${DIR}/dashboard/configure_kibana_dashboard.sh


# Register the same schema for the replicated topic wikipedia.parsed.replica as was created for the original topic wikipedia.parsed
# In this case the replicated topic will register with the same schema ID as the original topic
SCHEMA=$(docker-compose exec schemaregistry curl -X GET --cert /etc/kafka/secrets/schemaregistry.certificate.pem --key /etc/kafka/secrets/schemaregistry.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt https://schemaregistry:8085/subjects/wikipedia.parsed-value/versions/latest | jq .schema)
docker-compose exec schemaregistry curl -X POST --cert /etc/kafka/secrets/schemaregistry.certificate.pem --key /etc/kafka/secrets/schemaregistry.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"schema\": $SCHEMA}" https://schemaregistry:8085/subjects/wikipedia.parsed.replica-value/versions

echo -e "\nConfigure triggers and actions in Control Center:"
curl -X POST -H "Content-Type: application/json" -d '{"name":"Consumption Difference","clusterId":"'$(curl -X GET http://localhost:9021/2.0/clusters/kafka/ | jq --raw-output '.[0].clusterId')'","group":"connect-elasticsearch-ksql","metric":"CONSUMPTION_DIFF","condition":"GREATER_THAN","longValue":"0","lagMs":"10000"}' http://localhost:9021/2.0/alerts/triggers
curl -X POST -H "Content-Type: application/json" -d '{"name":"Under Replicated Partitions","clusterId":"default","condition":"GREATER_THAN","longValue":"0","lagMs":"60000","brokerClusters":{"brokerClusters":["'$(curl -X GET http://localhost:9021/2.0/clusters/kafka/ | jq --raw-output ".[0].clusterId")'"]},"brokerMetric":"UNDER_REPLICATED_TOPIC_PARTITIONS"}' http://localhost:9021/2.0/alerts/triggers
curl -X POST -H "Content-Type: application/json" -d '{"name":"Email Administrator","enabled":true,"triggerGuid":["'$(curl -X GET http://localhost:9021/2.0/alerts/triggers/ | jq --raw-output '.[0].guid')'","'$(curl -X GET http://localhost:9021/2.0/alerts/triggers/ | jq --raw-output '.[1].guid')'"],"maxSendRate":1,"intervalMs":"60000","email":{"address":"devnull@confluent.io","subject":"Confluent Control Center alert"}}' http://localhost:9021/2.0/alerts/actions

echo -e "Launching spark Sentiment Application "
chmod 755 ${PWD}/docker-spark/bin/launch_spark.sh
source ${PWD}/docker-spark/bin/launch_spark.sh

echo -e "\n\n\n******************************************************************"
echo -e "DONE! Connect to Confluent Control Center at http://localhost:9021"
echo -e "******************************************************************\n"
