<?php

class Hello {
    public static function handler($event = null, $context = null) {
        return [
            'statusCode' => 200,
            'body' => json_encode([
                'message' => 'Hello from Lambda/Php running offline!, Running on Php version: ' . phpversion() . ' - ' . getcwd(),
                'input' => $event,
                'context' => $context
            ]),
        ];
    }
}
