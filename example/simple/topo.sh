#!/usr/bin/env bash
set -e

ip netns add mptcp-client
ip netns add mptcp-server

sudo sysctl -w net.ipv4.conf.all.rp_filter=0

# 各NSでMPTCP有効化
ip netns exec mptcp-client sysctl -w net.mptcp.enabled=1
ip netns exec mptcp-server sysctl -w net.mptcp.enabled=1

# veth 2本作成
ip link add red-client netns mptcp-client type veth peer red-server netns mptcp-server
ip link add blue-client netns mptcp-client type veth peer blue-server netns mptcp-server

# アドレス付与
ip -n mptcp-server address add 10.0.0.1/24 dev red-server
ip -n mptcp-server address add 192.168.0.1/24 dev blue-server
ip -n mptcp-client address add 10.0.0.2/24 dev red-client
ip -n mptcp-client address add 192.168.0.2/24 dev blue-client

# UP
ip -n mptcp-server link set red-server up
ip -n mptcp-server link set blue-server up
ip -n mptcp-client link set red-client up
ip -n mptcp-client link set blue-client up

# 既存設定クリア＆上限調整（サーバ/クライアント）
ip -n mptcp-server  mptcp endpoint flush
ip -n mptcp-server  mptcp limits set subflow 2 add_addr_accepted 2
ip -n mptcp-client  mptcp endpoint flush
ip -n mptcp-client  mptcp limits set subflow 2 add_addr_accepted 2

# 確認
ip -n mptcp-server  mptcp limits show
ip -n mptcp-client  mptcp limits show
ip -n mptcp-client  mptcp endpoint show
