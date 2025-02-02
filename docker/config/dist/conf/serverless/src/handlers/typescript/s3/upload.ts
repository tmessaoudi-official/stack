import { S3 } from 'aws-sdk';
import { APIGatewayProxyHandler, APIGatewayProxyEvent, Context, Callback, APIGatewayProxyResult } from 'aws-lambda';

const s3 = new S3({
  endpoint: '${global_stack_process.customEnv.AWS_ENDPOINT_URL_S3}',
  s3ForcePathStyle: true,
});

export const handler: APIGatewayProxyHandler = async (event: APIGatewayProxyEvent, context: Context, callback: Callback<APIGatewayProxyResult>): Promise<APIGatewayProxyResult> => {
  const body = JSON.parse(event.body || '{}');
  const { fileName, fileContent } = body;

  if (!fileName || !fileContent) {
    return {
      statusCode: 400,
      body: JSON.stringify({ message: 'Missing fileName or fileContent' }),
    };
  }

  try {
    await s3
      .putObject({
        Bucket: process.env.S3_BUCKET as string,
        Key: fileName,
        Body: fileContent,
      })
      .promise();

    return {
      statusCode: 200,
      body: JSON.stringify({ message: `File ${fileName} uploaded successfully!` }),
    };
  } catch (error) {
    return {
      statusCode: 500,
      body: JSON.stringify({ message: 'Failed to upload file', error }),
    };
  }
};