package daisy;

import com.amazonaws.services.dynamodbv2.AmazonDynamoDB;
import com.amazonaws.services.dynamodbv2.AmazonDynamoDBClientBuilder;
import com.amazonaws.services.dynamodbv2.document.DynamoDB;
import com.amazonaws.services.dynamodbv2.document.Table;
import com.amazonaws.services.dynamodbv2.document.Item;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;

public class ApiGatewayToDynamoDBHandler implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

  private static final String TABLE_NAME = System.getenv("TABLE_NAME");

  private final AmazonDynamoDB client = AmazonDynamoDBClientBuilder.defaultClient();
  private final DynamoDB dynamoDB = new DynamoDB(client);
  private final Table table = dynamoDB.getTable(TABLE_NAME);

  @Override
  public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent request, Context context) {
    APIGatewayProxyResponseEvent response = new APIGatewayProxyResponseEvent();

    context.getLogger().log(TABLE_NAME);
    try {
      // Parse the request body (assumes JSON input)
      String body = request.getBody();

      // Create a new DynamoDB item (key-value pairs)
      Item item = Item.fromJSON(body);
      context.getLogger().log(item.toJSONPretty());
      context.getLogger().log("A");

      // Put the item into the DynamoDB table
      var o = table.putItem(item);
      context.getLogger().log(o.toString());
      context.getLogger().log("B");

      // Return a success response
      response.setStatusCode(200);
      response.setBody("{\"message\": \"Item added successfully\"}");
    } catch (Exception e) {
      context.getLogger().log("C");
      context.getLogger().log("------- Error: " + e.getMessage());
      response.setStatusCode(500);
      response.setBody("{\"error\": \"Failed to add item to DynamoDB\": "+e.getMessage()+"}");
    }
    return response;
  }
}