Add this at the end of the file !

if [ -d "/opt/$USER/sonar-scanner-cli/bin" ] ; then
    PATH="/opt/$USER/sonar-scanner-cli/bin:$PATH"
fi

if [ -d "/opt/$USER/task" ] ; then
    PATH="/opt/$USER/task:$PATH"
fi

if [ -d "/opt/$USER/bat" ] ; then
    PATH="/opt/$USER/bat:$PATH"
fi

if [ -d "/opt/$USER/go/bin" ] ; then
    PATH="/opt/$USER/go/bin:$PATH"
fi

if [ -d "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"/go/bin ]; then 
    PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/go/bin:${PATH}"
fi

if [ -d "${GOROOT}"/bin ]; then 
    PATH="${GOROOT}/bin:${PATH}"
fi

if [ -d "${ZIGPATH}" ]; then 
    PATH="${ZIGPATH}:${PATH}"
fi

if [ -d "${HURLPATH}" ]; then 
    PATH="${HURLPATH}:${PATH}"
fi