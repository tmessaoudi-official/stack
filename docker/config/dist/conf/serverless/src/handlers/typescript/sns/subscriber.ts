import { SNSHandler, SNSEvent, Context, Callback } from 'aws-lambda';

export const handler: SNSHandler = async (event: SNSEvent, context: Context, callback: Callback<void>): Promise<void> => {
  console.log('From Subscriber');
  console.log('SNS Event:', JSON.stringify(event, null, 2));

  for (const record of event.Records) {
    console.log('Message:', record.Sns.Message);
  }
};
