package es.uam.sentiment

import es.uam.sentiment.elasticsearch.ESWriter
import es.uam.sentiment.kafka.KafkaConsumer
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.avro._


/**
 * Hello world!
 *
 */
object SentimentAnalysisDriver {
  def main(args: Array[String]): Unit = {
    val esNodes = "127.0.0.1"
    val esPort = "9200"
    val schemaRegistryAddr = "https://schemaregistry:8085"
    val kafkaBrokers="kafka1:9091,kafka2:90922"
    val topic = "connect_twitter_status"

    val config = SentimentConfig(esNodes, esPort, kafkaBrokers, topic, schemaRegistryAddr)
    val sparkSession = Connection.createSparkSession(config)

    val sourceDF = KafkaConsumer.getSourceByAvroSchema(sparkSession, config)
    ESWriter.writeToElasticSearch(sparkSession, sourceDF)
  }





}
