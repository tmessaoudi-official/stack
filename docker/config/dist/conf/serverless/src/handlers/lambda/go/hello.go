package main

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"runtime"
)

// Response structure
type Response struct {
	Message string      `json:"message"`
	Input   interface{} `json:"input"`
	Context string      `json:"context"`
}

// Handler function for AWS Lambda
func handler(ctx context.Context, event events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Create the response body
	body := Response{
		Message: fmt.Sprintf("Hello from Lambda/Go running offline! Running on Go version: %s", runtime.Version()),
		Input:   event,
		Context: fmt.Sprintf("%v", ctx),
	}

	// Convert the body to JSON
	bodyJSON, err := json.Marshal(body)
	if err != nil {
		return events.APIGatewayProxyResponse{StatusCode: 500, Body: `{"error":"Failed to process the request"}`}, nil
	}

	// Return a successful response
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(bodyJSON),
	}, nil
}

func main() {
	// Start the Lambda handler
	lambda.Start(handler)
}