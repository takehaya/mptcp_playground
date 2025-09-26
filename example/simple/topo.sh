#!/usr/bin/env bash
set -e

ip netns add mptcp-client
ip netns add mptcp-server

# rp_filter 無効化
sysctl -w net.ipv4.conf.all.rp_filter=0
ip netns exec mptcp-client sysctl -w net.ipv4.conf.all.rp_filter=0
ip netns exec mptcp-client sysctl -w net.ipv4.conf.default.rp_filter=0
ip netns exec mptcp-server sysctl -w net.ipv4.conf.all.rp_filter=0
ip netns exec mptcp-server sysctl -w net.ipv4.conf.default.rp_filter=0

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

# mptcp関連の設定
# 1) 既存をクリア
ip -n mptcp-client mptcp endpoint flush
ip -n mptcp-server mptcp endpoint flush

# 2) 上限を引き上げる
# subflow 3, add_addr_accepted 2 の時だと以下の意味になる
# 自分から作れる subflow は 4 本まで（= init1 + subflow3 = 最大4本の同時フロー）
# 相手から受け入れる追加アドレスは 2 個まで
ip -n mptcp-client mptcp limits set subflow 3 add_addr_accepted 2
ip -n mptcp-server mptcp limits set subflow 3 add_addr_accepted 2

# 3) クライアントは両IFを subflow 可にする
ip netns exec mptcp-client ip mptcp endpoint add 192.168.0.2 dev blue-client subflow fullmesh
ip netns exec mptcp-client ip mptcp endpoint add 10.0.0.2 dev red-client subflow fullmesh

# 4) server は自分の 192.168.0.1 を "signal"（相手に通知）
ip netns exec mptcp-server ip mptcp endpoint add 192.168.0.1 dev blue-server signal

# 5) 確認
ip -n mptcp-client mptcp endpoint show
ip -n mptcp-client mptcp limits show
ip -n mptcp-server mptcp limits show

ip -n mptcp-server mptcp endpoint show

ip netns exec mptcp-server sysctl -w net.mptcp.allow_join_initial_addr_port=0