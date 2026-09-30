#!/bin/sh

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

export AP_CONTAINER_TYPE="${AP_CONTAINER_TYPE:-WORKER_AND_APP}"
export AP_PORT="${AP_PORT:-80}"

echo "AP_CONTAINER_TYPE: $AP_CONTAINER_TYPE"
echo "AP_PORT: $AP_PORT"

# Auto-generate worker token if not set and JWT secret is available
if [ -z "$AP_WORKER_TOKEN" ] && [ -n "$AP_JWT_SECRET" ]; then
    echo "Auto-generating AP_WORKER_TOKEN..."
    export AP_WORKER_TOKEN=$(node -e "
        const jwt = require('jsonwebtoken');
        const crypto = require('crypto');
        const token = jwt.sign(
            { id: crypto.randomUUID(), type: 'WORKER' },
            process.env.AP_JWT_SECRET,
            { expiresIn: '100y', keyid: '1', algorithm: 'HS256', issuer: 'activepieces' }
        );
        process.stdout.write(token);
    ")
fi

APP_SCRIPT="packages/server/api/dist/src/bootstrap.js"
WORKER_SCRIPT="packages/server/worker/dist/src/bootstrap.js"

FORWARD_PID=""
if [ -n "${HOST_PORT:-}" ] && [ "${HOST_PORT}" != "${AP_PORT}" ]; then
    node -e "
        const net = require('net');
        const from = parseInt(process.env.HOST_PORT, 10);
        const to = parseInt(process.env.AP_PORT || '80', 10);
        for (const host of ['127.0.0.1', '::1']) {
            const server = net.createServer((client) => {
                const upstream = net.connect(to, '127.0.0.1', () => {
                    client.pipe(upstream);
                    upstream.pipe(client);
                });
                upstream.on('error', () => client.destroy());
                client.on('error', () => upstream.destroy());
            });
            server.on('error', (err) => console.error('port-forward ' + host + ':' + from + ' failed: ' + err.message));
            server.listen(from, host, () => console.log('forwarding ' + host + ':' + from + ' -> 127.0.0.1:' + to));
        }
    " &
    FORWARD_PID=$!
fi

echo "Starting Activepieces (${AP_CONTAINER_TYPE} mode)"

case "$AP_CONTAINER_TYPE" in
    APP)
        exec node --enable-source-maps "$APP_SCRIPT"
        ;;
    WORKER)
        exec node --enable-source-maps "$WORKER_SCRIPT"
        ;;
    WORKER_AND_APP)
        AP_CONTAINER_TYPE=APP node --enable-source-maps "$APP_SCRIPT" &
        app_pid=$!
        node --enable-source-maps "$WORKER_SCRIPT" &
        worker_pid=$!

        trap 'kill "$app_pid" "$worker_pid" "$FORWARD_PID" 2>/dev/null' TERM INT

        while kill -0 "$app_pid" 2>/dev/null && kill -0 "$worker_pid" 2>/dev/null; do
            sleep 1
        done

        kill "$app_pid" "$worker_pid" "$FORWARD_PID" 2>/dev/null
        exit 1
        ;;
    *)
        echo "Unknown AP_CONTAINER_TYPE: $AP_CONTAINER_TYPE" >&2
        exit 1
        ;;
esac
