package es.uam.sentiment

case class SentimentConfig(es_nodes: String,
                  es_port: String,
                  kafka_brokers: String,
                  kafka_topic: String,
                  schemaResgistryUrl: String)
