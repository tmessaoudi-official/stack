import { APIGatewayProxyHandler, APIGatewayProxyEvent, Context, Callback, APIGatewayProxyResult } from 'aws-lambda';

export const handler: APIGatewayProxyHandler = async (event: APIGatewayProxyEvent, context: Context, callback: Callback<APIGatewayProxyResult>): Promise<APIGatewayProxyResult> => {
  console.log('S3 Event');
  console.log('Event: ', JSON.stringify(event));
  console.log('Context: ', JSON.stringify(context));
  console.log('Env: ', JSON.stringify(process.env));

  return {
    statusCode: 200,
    body: ''
  }
};