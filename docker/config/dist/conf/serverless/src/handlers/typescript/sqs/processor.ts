import { SQSHandler, SQSEvent, Context, Callback, SQSBatchResponse } from 'aws-lambda';

export const handler: SQSHandler = async (event: SQSEvent, context: Context, callback: Callback<void | SQSBatchResponse>): Promise<void | SQSBatchResponse> => {
  try {
    for (const record of event.Records) {
      const message = record.body;
      console.log('Processing message:', message);

      // Add your message processing logic here
    }

    callback(null, {
      batchItemFailures: [],
    });
  } catch (error) {
    console.error('Error processing messages:', error);
    callback(<Error | string | null>error);
  }
};
