module.exports.handler = async (event, context) => {
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: `Hello from Lambda/JS running offline!, Running on Node.js version: ${process.version} - ${process.cwd()}`,
            input: event,
            context: context
        }),
    };
};