import AWS from 'aws-sdk';
import { APIGatewayProxyHandler, APIGatewayProxyEvent, Context, Callback, APIGatewayProxyResult } from 'aws-lambda';

const sns = new AWS.SNS({
  endpoint: '${global_stack_process.customEnv.AWS_ENDPOINT_URL_SNS}', // Use the local SNS emulator
  region: '${global_stack_process.customEnv.AWS_REGION}',
});

export const handler: APIGatewayProxyHandler = async (event: APIGatewayProxyEvent, context: Context, callback: Callback<APIGatewayProxyResult>): Promise<APIGatewayProxyResult> => {  
  const message = JSON.parse(event.body || '{}').message || 'Hello from SNS!';
  const params = {
    Message: message,
    TopicArn: 'arn:aws:sns:${global_stack_process.customEnv.AWS_REGION}:${global_stack_process.customEnv.AMAZON_ACCOUNT_ID}:local-topic',
  };

  try {
    await sns.publish(params).promise();
    console.log('Published message :', message);
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Message published to SNS!' }),
    };
  } catch (error) {
    console.error('Error publishing to SNS:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'Failed to publish message' }),
    };
  }
};