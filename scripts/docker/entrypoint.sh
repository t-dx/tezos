#!/bin/sh

set -e

bin_dir="$(cd "$(dirname "$0")" && echo "$(pwd -P)/")"

: ${DATA_DIR:="/var/run/tezos"}

: ${NODE_HOST:="node"}
: ${NODE_RPC_PORT:="8732"}

node="/usr/local/bin/tezos-node"
client="/usr/local/bin/tezos-client"
admin_client="/usr/local/bin/tezos-admin-client"
baker="/usr/local/bin/tezos-alpha-baker"
endorser="/usr/local/bin/tezos-alpha-endorser"
accuser="/usr/local/bin/tezos-alpha-accuser"

client_dir="$DATA_DIR/client"
node_dir="$DATA_DIR/node"
node_data_dir="$node_dir/data"

. "$bin_dir/entrypoint.inc.sh"

command=${1:-tezos-node}
shift 1

case $command in
    tezos-node)
        launch_node "$@"
    ;;
    tezos-baker)
        launch_baker "$@"
        ;;
    tezos-endorser)
        launch_endorser "$@"
        ;;
    tezos-accuser)
        launch_accuser "$@"
        ;;
    tezos-client)
        configure_client
        exec "$client" "$@"
        ;;
    tezos-admin-client)
        configure_client
        exec "$admin_client" "$@"
        ;;
    *)
        cat <<EOF
Available commands:
- tezos-node [args]
- tezos-client [args]
- tezos-baker [keys]
- tezos-endorser [keys]
EOF
        ;;
esac
