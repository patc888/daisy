package daisy;

import com.amazonaws.services.dynamodbv2.model.StreamRecord;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.DynamodbEvent;
import com.amazonaws.services.kinesis.AmazonKinesis;
import com.amazonaws.services.kinesis.AmazonKinesisClientBuilder;
import com.amazonaws.services.kinesis.model.PutRecordRequest;


import java.nio.ByteBuffer;

public class DynamoDBToKinesisHandler implements RequestHandler<DynamodbEvent, String> {

  private static final String KINESIS_STREAM_NAME = System.getenv("KINESIS_STREAM_NAME");
  private final AmazonKinesis kinesisClient = AmazonKinesisClientBuilder.defaultClient();

  @Override
  public String handleRequest(DynamodbEvent event, Context context) {
    for (DynamodbEvent.DynamodbStreamRecord dynamodbRecord : event.getRecords()) {
      if ("INSERT".equals(dynamodbRecord.getEventName()) || "MODIFY".equals(dynamodbRecord.getEventName())) {
        var streamRecord = dynamodbRecord.getDynamodb();
        String recordData = streamRecord.getNewImage().toString();

        sendToKinesis(recordData);
        context.getLogger().log("Sent record to Kinesis: " + recordData);
      }
    }
    return "Success";
  }

  private void sendToKinesis(String recordData) {
    PutRecordRequest putRecordRequest = new PutRecordRequest()
        .withStreamName(KINESIS_STREAM_NAME)
        .withPartitionKey("partitionKey") // Use a meaningful partition key, e.g., hash key
        .withData(ByteBuffer.wrap(recordData.getBytes()));
    kinesisClient.putRecord(putRecordRequest);
  }
}