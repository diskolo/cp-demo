package es.uam.sentiment.elasticsearch

import org.apache.spark.sql.{DataFrame, SparkSession}

object ESWriter {

  def writeToElasticSearch(sparkSession: SparkSession, elasticDF: DataFrame): Unit = {
    //Configure sparksession to write to es
    //write the dataframe to elasticseach
    elasticDF.writeStream
      .outputMode("append")
      .format("org.elasticsearch.spark.sql")
      .option("checkpointLocation", "path-to-checkpointing")
      .start("sentiment/_doc")
      .awaitTermination()
  }

}
