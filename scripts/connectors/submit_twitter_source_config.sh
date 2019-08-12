#!/bin/bash

HEADER="Content-Type: application/json"
DATA=$( cat << EOF
{
  "name":"twitter-connector",
  "config":{
    "tasks.max":"1",
    "connector.class":"com.github.jcustenborder.kafka.connect.twitter.TwitterSourceConnector",
    "twitter.oauth.accessTokenSecret":"6tYYQ2WkeiPQcSyx4qrYzGCgr1oMP4gkZdI3XPt315Py0",
    "process.deletes": false,
    "filter.keywords": "Carrefour,carrefour",
    "kafka.status.topic":"connect_twitter_status",
    "kafka.delete.topic":"connect_twitter_delete",
    "twitter.oauth.consumerSecret":"ins6jYjCRZbRHFxcFEG8vlFWkTg16JK5YEMxG5HHKnGJkzxjpo",
    "twitter.oauth.accessToken":"831122361390919681-zwp1GSOvGLx0aiNmkbPZnkHRHqzhzCT",
    "twitter.oauth.consumerKey":"zzpm3ncxQueqZTRdignBa7KLn"
  }
}
EOF
)

docker-compose exec connect curl -X POST -H "${HEADER}" --data "${DATA}" --cert /etc/kafka/secrets/connect.certificate.pem --key /etc/kafka/secrets/connect.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt https://connect:8083/connectors
