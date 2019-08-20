package es.uam.sentiment.kafka

import java.util

import io.confluent.kafka.schemaregistry.client.rest.RestService
import org.apache.avro.Schema
import org.apache.spark.sql.{DataFrame, SparkSession, avro}
import org.apache.spark.sql.functions._
import java.util.HashMap

import es.uam.sentiment.SentimentConfig
import io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient

object KafkaConsumer {


  /**
   *
   * @param sentimentConfig
   * @return
   */
  def getSchemaFromSchemaRegistry(sentimentConfig: SentimentConfig): String = {
    val subjectValueName = s"${sentimentConfig.kafka_topic}-value"
    println(s"Searching for: $subjectValueName subject........")

    //create RestService object
    val restService = new RestService(sentimentConfig.schemaResgistryUrl)
    val valueRestResponseSchema = restService.getLatestVersion(subjectValueName)

    //Use Avro parsing classes to get Avro Schema
    val parser = new Schema.Parser
    val topicValueAvroSchema = parser.parse(valueRestResponseSchema.getSchema).toString(true)
    println(s"The schema is: $topicValueAvroSchema")
    topicValueAvroSchema
  }

  /**
   *
   * @param spark
   * @param avroSchema
   * @return
   */
  def createSourceDF(spark: SparkSession, avroSchema: String, sentimentConfig: SentimentConfig): DataFrame = {
    spark.readStream.format("kafka")
      .option("kafka.bootstrap.servers", sentimentConfig.kafka_brokers)
      .option("subscribe", sentimentConfig.kafka_topic)
      .load()
      .select(avro.from_avro(col("value"), avroSchema))
  }

  def getSourceByAvroSchema(sparkSession: SparkSession, sentimentConfig: SentimentConfig): DataFrame = {
    val avroSchema = getSchemaFromSchemaRegistry(sentimentConfig)
    createSourceDF(sparkSession, avroSchema, sentimentConfig)
  }

  /**
   *
   * @param sourceDF
   * @return
   */
  def addSentimentAnalysis(sourceDF: DataFrame): DataFrame = ???

}
