use aws_lambda_events::apigw::ApiGatewayProxyRequest;
use lambda_runtime::{service_fn, LambdaEvent, Context, Error};
use serde_json::json;

#[tokio::main]
async fn main() -> Result<(), Error> {
    let handler = service_fn(func);
    lambda_runtime::run(handler).await?;
    Ok(())
}

async fn func(event: LambdaEvent<ApiGatewayProxyRequest>) -> Result<serde_json::Value, Error> {
    let (event, context) = event.into_parts();
    let message = format!(
        "Hello from Lambda/Rust running offline! Running on Rust version: {} - {:?}",
        rustc_version_runtime::version(),
        std::env::current_dir().unwrap()
    );

    let response = json!({
        "statusCode": 200,
        "body": json!({
            "message": message,
            "input": event,
            "context": context
        }).to_string()
    });

    Ok(response)
}