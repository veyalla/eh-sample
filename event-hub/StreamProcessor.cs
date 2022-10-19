
using System.Text;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Processor;
using Azure.Storage.Blobs;
using Azure.Messaging.WebPubSub;
using Newtonsoft.Json;
using Azure.Messaging.EventHubs.Producer;

namespace event_hub;
public class StreamProcessor : BackgroundService
{
    private readonly ILogger<StreamProcessor> _logger;  
    private readonly WebPubSubServiceClient _serviceClient;
    private readonly bool _isPubSub = false;
    private readonly string _podName;
    private readonly EventProcessorClient processor;
    private readonly EventHubBufferedProducerClient producer; 

    public StreamProcessor(IConfiguration configuration, ILogger<StreamProcessor> logger)
    {
        _logger = logger;
        var webPubSubConnectionString = configuration.GetValue<string>("WEBPUBSUB_CONNECTION_STRING");
        if(!string.IsNullOrEmpty(webPubSubConnectionString))
        {
            _serviceClient = new WebPubSubServiceClient(webPubSubConnectionString, "stream");
            _isPubSub = true;
        }
        _podName = configuration.GetValue<string>("CONTAINER_APP_REVISION");

        var storageClient = new BlobContainerClient(configuration.GetValue<string>("STORAGE_CONNECTION_STRING"), configuration.GetValue<string>("STORAGE_BLOB_NAME"));
        this.processor = new EventProcessorClient(storageClient, configuration.GetValue<string>("EVENTHUB_D2C_CONSUMER_GROUP"), configuration.GetValue<string>("EVENTHUB_D2C_CONNECTION_STRING"), configuration.GetValue<string>("EVENTHUB_D2C_NAME"));

        string producerEventHub = configuration.GetValue<string>("EVENTHUB_C2D_NAME");
        string producerEventHubCS = configuration.GetValue<string>("EVENTHUB_C2D_CONNECTION_STRING");

        this.producer = new EventHubBufferedProducerClient(producerEventHubCS, producerEventHub);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        this.processor.ProcessEventAsync += ProcessEventHandler;
        this.processor.ProcessErrorAsync += ProcessErrorHandler;

        this.producer.SendEventBatchSucceededAsync += SendBatchSucceeded;
        this.producer.SendEventBatchFailedAsync += SendBatchFailed;

        // Start the processing
        await processor.StartProcessingAsync();

        while (!stoppingToken.IsCancellationRequested)
        {
            var message = $"{_podName}: StreamProcessor running at: {DateTimeOffset.Now}.";
            _logger.LogInformation(message);
            if(_isPubSub)
            {
                _serviceClient.SendToAll(message);
            }
            await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
        }

        _logger.LogInformation("Closing message pump");
        processor.ProcessEventAsync -= ProcessEventHandler;
        processor.ProcessErrorAsync -= ProcessErrorHandler;
        // Stop the processing
        await processor.StopProcessingAsync();

        _logger.LogInformation("Message pump closed : {Time}", DateTimeOffset.UtcNow);
    }

    private Task SendBatchFailed(SendEventBatchFailedEventArgs arg)
    {
        string logMsg = $"Failed to publish events to EventHub because of error: {arg.Exception.Message}";
        _logger.LogError(logMsg);
        if (_isPubSub)
        {
            _serviceClient.SendToAll(logMsg);
        }
        return Task.CompletedTask;
    }

    private Task SendBatchSucceeded(SendEventBatchSucceededEventArgs arg)
    {
        string logMsg = $"Published {arg.EventBatch.Count} events to EventHub";
        _logger.LogInformation(logMsg);
        if (_isPubSub)
        {
            _serviceClient.SendToAll(logMsg);
        }
        return Task.CompletedTask;
    }

    private Task ProcessErrorHandler(ProcessErrorEventArgs arg)
    {
        throw new NotImplementedException();
    }

    private async Task ProcessEventHandler(ProcessEventArgs eventArgs)
    {
        string msgData = Encoding.UTF8.GetString(eventArgs.Data.EventBody.ToArray());
        var logMessage = $"{_podName}: Received Event Hub message {msgData}";
        _logger.LogInformation(logMessage);
        if(_isPubSub)
        {
            _serviceClient.SendToAll(logMessage);
        }
        await eventArgs.UpdateCheckpointAsync(eventArgs.CancellationToken);

        string replyMessage = ProcessInputMessage(msgData);
        if (!string.IsNullOrWhiteSpace(replyMessage))
        {
            await this.producer.EnqueueEventAsync(new EventData(replyMessage));
        }
    }

    string ProcessInputMessage(string msgString)
    {
        ArgumentNullException.ThrowIfNull(msgString);           
        dynamic? parsedJson = JsonConvert.DeserializeObject(msgString);
        string? itemVal = parsedJson?.data?.item;

        if (!string.IsNullOrWhiteSpace(itemVal))
        {
            Dictionary<string, object> responseMessage = new Dictionary<string, object>()
            {
                ["item"] = itemVal,
                ["processed-by"] = this._podName
            };
            string responseMessageString = JsonConvert.SerializeObject(responseMessage);
            return responseMessageString;
        }

        return string.Empty;
    }
}
