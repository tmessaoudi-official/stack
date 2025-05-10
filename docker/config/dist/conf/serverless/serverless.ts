import { AWS } from '@serverless/typescript';

const serverlessConfiguration: AWS = {
  service: 'serverless-framework',
  frameworkVersion: "${global_stack_process.customEnv.SERVERLESS_VERSION}",
  custom: {
    'serverless-offline': {
      accountId: '${global_stack_process.customEnv.AMAZON_ACCOUNT_ID}',
      host: '0.0.0.0',
      accessKeyId: "${global_stack_process.customEnv.AWS_ACCESS_KEY_ID}",
      secretAccessKey: "${global_stack_process.customEnv.AWS_SECRET_ACCESS_KEY}",
      region: "${global_stack_process.customEnv.AWS_REGION}",
    },
    s3: {
      accountId: '${global_stack_process.customEnv.AMAZON_ACCOUNT_ID}',
      address: '0.0.0.0',
      region: "${global_stack_process.customEnv.AWS_REGION}",
      cors: './conf/cors/s3/config.xml',
      accessKeyId: "${global_stack_process.customEnv.AWS_ACCESS_KEY_ID}",
      secretAccessKey: "${global_stack_process.customEnv.AWS_SECRET_ACCESS_KEY}",
      directory: './var/storage/s3-buckets',
      forcePathStyle: false,
      vhost: false,
      vhostBuckets: false,
      allowMismatchedSignatures: true
    },
    'serverless-offline-sqs': {
      accountId: '${global_stack_process.customEnv.AMAZON_ACCOUNT_ID}',
      autoCreate: true,
      apiVersion: '2012-11-05',
      endpoint: '${global_stack_process.customEnv.AWS_ENDPOINT_URL_SQS}',
      region: "${global_stack_process.customEnv.AWS_REGION}",
      accessKeyId: "${global_stack_process.customEnv.AWS_ACCESS_KEY_ID}",
      secretAccessKey: "${global_stack_process.customEnv.AWS_SECRET_ACCESS_KEY}",
      skipCacheInvalidation: false,
    },
    'serverless-offline-sns': {
      accountId: '${global_stack_process.customEnv.AMAZON_ACCOUNT_ID}',
      debug: true,
      host: '0.0.0.0',
      accessKeyId: "${global_stack_process.customEnv.AWS_ACCESS_KEY_ID}",
      secretAccessKey: "${global_stack_process.customEnv.AWS_SECRET_ACCESS_KEY}",
    },
  },
  provider: {
    name: 'aws',
    runtime: 'provided.al2023',
    region: "${global_stack_process.customEnv.AWS_REGION}",
    iam: {
      role: {
        statements: [
          {
            Effect: 'Allow',
            Action: [
              's3:*'
            ],
            Resource: "arn:aws:s3:::local-bucket/*"
          }
        ]
      },
    },
  },
  plugins: [
    'serverless-s3-local', 
    'serverless-offline-sqs', 
    'serverless-offline-sns', 
    'serverless-offline'
  ],
  resources: {
    Resources: {
      s3LocalBucket: {
        Type: 'AWS::S3::Bucket',
        Properties: {
          BucketName: 'local-bucket',
        },
      },
      sqsLocalQueue: {
        Type: 'AWS::SQS::Queue',
        Properties: {
          QueueName: 'local-queue'
        },
      },
      snsLocalTopic: {
        Type: 'AWS::SNS::Topic',
        Properties: {
          TopicName: 'local-topic'
        },
      },
    },
  },
  functions: {
    'nodejs-s3-hook-ts': {
      runtime: 'nodejs22.x',
      handler: 'build/s3/hook.handler',
      events: [
        {
          s3: {
            bucket: 'local-bucket',
            event: 's3:*',
          },
        },
      ],
    },
    'nodejs-sqs-processor-ts': {
      runtime: 'nodejs22.x',
      handler: 'build/sqs/processor.handler',
      events: [
        {
          sqs: {
            arn: { 
              'Fn::GetAtt': ['sqsLocalQueue', 'Arn']
            }
          }
        }
      ]
    },
    'nodejs-sns-publisher-ts': {
      runtime: 'nodejs22.x',
      handler: 'build/sns/publisher.handler',
      events: [
        {
          http: {
            path: '/lambda/nodejs/sns/publish-ts',
            method: 'post',
          },
        },
      ],
    },
    'nodejs-sns-subscriber-ts': {
      runtime: 'nodejs22.x',
      handler: 'build/sns/subscriber.handler',
      events: [
        {
          sns: {
            topicName: 'local-topic',
          },
        },
      ],
    },
  },
};

module.exports = serverlessConfiguration;