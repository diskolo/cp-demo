package es.uam.sentiment

import org.apache.spark.sql.SparkSession
import org.elasticsearch.hadoop.cfg.ConfigurationOptions

object Connection {

  def createSparkSession(config: SentimentConfig): SparkSession =
    SparkSession
      .builder()
      .config(ConfigurationOptions.ES_NODES, config.es_nodes )
      .config(ConfigurationOptions.ES_PORT, config.es_nodes)
      .appName("Sentiment Analysis")
      .getOrCreate()


}
