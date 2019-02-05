#!/usr/bin/env bash

# Exit script as soon as a command fails.
set -o errexit

# Executes cleanup function at script exit.
trap cleanup EXIT

cleanup() {
  # Kill ganache instance if it's still running
  if [ -n "$ganache_pid" ] && ps -p $ganache_pid > /dev/null; then
    kill -9 $ganache_pid
  fi
}

start_ganache() {
  echo "Starting ganache-cli..."
  nohup npx ganache-cli -e 10000 -a 240 -p 8545 > /dev/null &
  ganache_pid=$!
  sleep 3
  echo "Running ganache-cli with pid ${ganache_pid}"
}

run_tests() {
  if [ "$SOLIDITY_COVERAGE" = true ]; then
    echo "Measuring coverage..."
    node_modules/.bin/solidity-coverage
    if [ "$CONTINUOUS_INTEGRATION" = true ]; then
      cat coverage/lcov.info | node_modules/.bin/coveralls
    fi
  else
    echo "Compiling..."
    truffle compile
    echo "Running tests..."
    truffle test --network local "$@"
  fi
}

start_ganache
run_tests
