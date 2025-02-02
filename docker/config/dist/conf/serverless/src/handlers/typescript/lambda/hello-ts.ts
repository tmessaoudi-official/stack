import { APIGatewayProxyHandler, APIGatewayProxyEvent, Context, Callback, APIGatewayProxyResult } from 'aws-lambda';

export const handler: APIGatewayProxyHandler = async (event: APIGatewayProxyEvent, context: Context, callback: Callback<APIGatewayProxyResult>): Promise<APIGatewayProxyResult> => {
  return {
    statusCode: 200,
    body: JSON.stringify({
      message: `Hello from Lambda/TS running offline!, Running on Node.js version: ${process.version} - ${process.cwd()}`,
      input: event,
      context: context
    }),
  };
};