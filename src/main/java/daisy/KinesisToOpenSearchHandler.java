package daisy;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.KinesisEvent;
import org.apache.http.HttpHost;
import org.opensearch.client.RestClient;
import org.opensearch.client.opensearch.OpenSearchClient;
import org.opensearch.client.opensearch.core.IndexRequest;
import org.opensearch.client.transport.rest_client.RestClientTransport;
import org.opensearch.common.xcontent.json.JsonXContent;
import org.opensearch.client.json.jackson.JacksonJsonpMapper;
import org.opensearch.core.xcontent.DeprecationHandler;
import org.opensearch.core.xcontent.NamedXContentRegistry;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

public class KinesisToOpenSearchHandler implements RequestHandler<KinesisEvent, String> {

  private static final String OPENSEARCH_ENDPOINT = System.getenv("OPENSEARCH_ENDPOINT");
  private static final String INDEX_NAME = "example-index";

  // Initialize the OpenSearch client using the new Java client
  private final OpenSearchClient openSearchClient = new OpenSearchClient(
      new RestClientTransport(
          RestClient.builder(HttpHost.create(OPENSEARCH_ENDPOINT)).build(),
          new JacksonJsonpMapper()
      )
  );

  @Override
  public String handleRequest(KinesisEvent event, Context context) {
    try {
      for (KinesisEvent.KinesisEventRecord record : event.getRecords()) {
        // Deserialize the Kinesis data (assuming JSON format)
        String jsonData = new String(record.getKinesis().getData().array());

        indexToOpenSearch(jsonData);
        context.getLogger().log("Indexed record to OpenSearch: " + jsonData);
      }
    } catch (Exception e) {
      context.getLogger().log("Error indexing record to OpenSearch: " + e.getMessage());
    }
    return "Success";
  }

  private void indexToOpenSearch(String jsonData) throws Exception {
    // Convert JSON string to a Map for indexing
    var inputStream = new ByteArrayInputStream(jsonData.getBytes());
    Map<String, Object> document = JsonXContent.jsonXContent.createParser(NamedXContentRegistry.EMPTY,
        DeprecationHandler.THROW_UNSUPPORTED_OPERATION, inputStream).map();

    // Build the IndexRequest with the document
    IndexRequest<Map<String, Object>> indexRequest = new IndexRequest.Builder<Map<String, Object>>()
        .index(INDEX_NAME)
        .document(document)
        .build();

    // Index the document into OpenSearch
    openSearchClient.index(indexRequest);
  }
}