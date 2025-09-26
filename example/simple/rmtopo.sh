#!/usr/bin/env bash
set -e

ip netns del mptcp-client
ip netns del mptcp-server