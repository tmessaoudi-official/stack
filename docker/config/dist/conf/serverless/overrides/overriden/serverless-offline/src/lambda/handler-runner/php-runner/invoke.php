<?php

class FakeLambdaContext {
    public $awsRequestId;
    public $clientContext;
    public $functionName;
    public $functionVersion;
    public $identity;
    public $invokedFunctionArn;
    public $logGroupName;
    public $logStreamName;
    public $memoryLimitInMB;
    private $timeout;
    private $createdTime;

    public function __construct(array $context) {
        $this->awsRequestId = $context['awsRequestId'] ?? null;
        $this->clientContext = $context['clientContext'] ?? null;
        $this->functionName = $context['functionName'] ?? null;
        $this->functionVersion = $context['functionVersion'] ?? null;
        $this->identity = $context['identity'] ?? null;
        $this->invokedFunctionArn = $context['invokedFunctionArn'] ?? null;
        $this->logGroupName = $context['logGroupName'] ?? null;
        $this->logStreamName = $context['logStreamName'] ?? null;
        $this->memoryLimitInMB = $context['memoryLimitInMB'] ?? null;
        $this->timeout = $context['timeout'] ?? 3; // Default timeout
        $this->createdTime = microtime(true);
    }

    public function getRemainingTimeInMillis(): int {
        return max(($this->timeout * 1000) - round((microtime(true) - $this->createdTime) * 1000), 0);
    }
}

// function attachTty() {
//     if (PHP_OS_FAMILY !== 'Windows' && posix_isatty(STDIN) === false && file_exists('/dev/tty')) {
//         $stdin = fopen('/dev/tty', 'a+');
//         if ($stdin) {
//             fclose(STDIN);
//             define('STDIN', $stdin);
//         } else {
//             echo "tty unavailable" . PHP_EOL;
//         }
//     }
// }

if (basename(__FILE__) === basename($_SERVER['PHP_SELF'])) {
    if ($argc < 3) {
        echo "Usage: invoke.php <handler_path> <handler_name>\n";
        exit(1);
    }
    
    $handlerPath = $argv[1];
    $handlerName = $argv[2];
    
    $input = json_decode(file_get_contents('php://stdin'), true) ?? [];
    
    require_once "./$handlerPath.php";
    
    $handlerParts = explode('.', $handlerName);
    $handlerMethod = array_pop($handlerParts);
    $handlerClass = $handlerParts ? implode('\\', $handlerParts) : null;
    
    // attachTty();
    
    $context = new FakeLambdaContext($input['context'] ?? []);
    $event = $input['event'] ?? [];
    
    if ($handlerClass) {
        $result = call_user_func([$handlerClass, $handlerMethod], ['event' => $event, 'context' => $context]);
    } else {
        $result = call_user_func($handlerMethod, ['event' => $event, 'context' => $context]);
    }
    
    echo json_encode(['__offline_payload__' => $result]) . "\n";
}
