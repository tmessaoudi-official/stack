use lambda_http::{run, service_fn, Body, Request, Response};
use lambda_runtime::{Context, Error};
use serde_json::json;
use std::env;
use std::fs;

async fn handler(event: Request, context: Context) -> Result<Response<Body>, Error> {
    // Get the current working directory (equivalent to process.cwd() in Node.js)
    let cwd = env::current_dir().unwrap_or_else(|_| ".".into());
    
    // Create the response JSON
    let response_body = json!({
        "message": format!(
            "Hello from Lambda/Rust running offline! Running on Rust version: {} - {:?}",
            rustc_version_runtime::version(),
            cwd
        ),
        "input": event,
        "context": json!(context)
    });

    Ok(Response::builder()
        .status(200)
        .header("Content-Type", "application/json")
        .body(Body::Text(response_body.to_string()))?)
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    run(service_fn(handler)).await
}