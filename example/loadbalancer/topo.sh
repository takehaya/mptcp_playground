#!/usr/bin/env bash
set -euo pipefail

# ===== パラメータ =====
# client側の2回線サブネット
NETA=10.0.1.0/24
NETB=10.0.2.0/24
C_A=10.0.1.2
L_A=10.0.1.1
C_B=10.0.2.2
L_B=10.0.2.1

# LB内のサーバー側ブリッジ用サブネット
SNET=172.16.0.0/24
S1=172.16.0.11
S2=172.16.0.12
S3=172.16.0.13

# VIPセグメント（client からはルーティング）
# 共有VIP: 198.51.100.10:443
# 固有VIP: 198.51.100.11:5001 -> s1, .12:5002 -> s2, .13:5003 -> s3
VIP_NET=198.51.100.0/24
VIP_SHARED=198.51.100.10
VIP_S1=198.51.100.11
VIP_S2=198.51.100.12
VIP_S3=198.51.100.13

# バックエンドの実ポート（http.server用）
BACKEND_PORT=8080

cleanup() {
  ip netns del client 2>/dev/null || true
  ip netns del lb 2>/dev/null || true
  ip netns del s1 2>/dev/null || true
  ip netns del s2 2>/dev/null || true
  ip netns del s3 2>/dev/null || true
}
trap cleanup ERR

cleanup

# ===== NS 作成 =====
ip netns add client
ip netns add lb
ip netns add s1
ip netns add s2
ip netns add s3

# ===== veth: client<->lb（2系統） =====
ip link add cA type veth peer name lA
ip link add cB type veth peer name lB
ip link set cA netns client
ip link set cB netns client
ip link set lA netns lb
ip link set lB netns lb

# ===== veth: lb(br)<->servers =====
ip link add ls1 type veth peer name s1e
ip link add ls2 type veth peer name s2e
ip link add ls3 type veth peer name s3e
ip link set ls1 netns lb
ip link set ls2 netns lb
ip link set ls3 netns lb
ip link set s1e netns s1
ip link set s2e netns s2
ip link set s3e netns s3

# ===== LB: br 作成 =====
ip netns exec lb ip link add br0 type bridge
ip netns exec lb ip link set br0 up
for i in ls1 ls2 ls3; do
  ip netns exec lb ip link set $i master br0
  ip netns exec lb ip link set $i up
done

# ===== アドレス設定 =====
# client
ip netns exec client ip addr add ${C_A}/24 dev cA
ip netns exec client ip addr add ${C_B}/24 dev cB
ip netns exec client ip link set cA up
ip netns exec client ip link set cB up
ip netns exec client ip link set lo up

# lb (client 側IF)
ip netns exec lb ip addr add ${L_A}/24 dev lA
ip netns exec lb ip addr add ${L_B}/24 dev lB
ip netns exec lb ip link set lA up
ip netns exec lb ip link set lB up
ip netns exec lb ip link set lo up

# lb (server 側 br0 にゲート用IP)
ip netns exec lb ip addr add 172.16.0.1/24 dev br0

# servers
ip netns exec s1 ip addr add ${S1}/24 dev s1e
ip netns exec s2 ip addr add ${S2}/24 dev s2e
ip netns exec s3 ip addr add ${S3}/24 dev s3e
for ns in s1 s2 s3; do
  ip netns exec $ns ip link set lo up
  ip netns exec $ns ip link set ${ns}e up
  ip netns exec $ns ip route add default via 172.16.0.1
done

# ===== ルーティング（client側）=====
# VIPセグメントは lA/lB を経由できるように2つのルール/テーブルを用意
ip netns exec client ip rule add from ${C_A} table 100
ip netns exec client ip rule add from ${C_B} table 200
ip netns exec client ip route add ${NETA} dev cA table 100
ip netns exec client ip route add ${NETB} dev cB table 200
ip netns exec client ip route add default via ${L_A} dev cA table 100
ip netns exec client ip route add default via ${L_B} dev cB table 200
# メインテーブルから VIP_NET への経路を両方に分散できるようスコープ明示
ip netns exec client ip route add ${VIP_NET} nexthop via ${L_A} dev cA nexthop via ${L_B} dev cB

# ===== LB: VIP を lo に割り当て（/32）=====
ip netns exec lb ip addr add ${VIP_SHARED}/32 dev lo
ip netns exec lb ip addr add ${VIP_S1}/32 dev lo
ip netns exec lb ip addr add ${VIP_S2}/32 dev lo
ip netns exec lb ip addr add ${VIP_S3}/32 dev lo

# ===== フォワーディング・MPTCP sysctl =====
for ns in client lb s1 s2 s3; do
  ip netns exec $ns sysctl -q net.ipv4.ip_forward=1 || true
  ip netns exec $ns sysctl -q net.mptcp.enabled=1 || true
done
# サーバーは "初回のIP/PortではJOINしない" 推奨
for ns in s1 s2 s3; do
  ip netns exec $ns sysctl -q net.mptcp.allow_join_initial_addr_port=0 || true
done

# ===== nftables: NAT(DNAT) & MASQ =====
ip netns exec lb nft -f - <<'NFT'
flush ruleset
table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;

    # 共有VIP: ハッシュで s1/s2/s3 に分散（:443 -> :8080）
    ip daddr 198.51.100.10 tcp dport 443 dnat to numgen random mod 3 map { 0 : 172.16.0.11:8080, 1 : 172.16.0.12:8080, 2 : 172.16.0.13:8080 }

    # 固有VIP/Port -> 対応サーバ固定（:500x -> :8080）
    ip daddr 198.51.100.11 tcp dport 5001 dnat to 172.16.0.11:8080
    ip daddr 198.51.100.12 tcp dport 5002 dnat to 172.16.0.12:8080
    ip daddr 198.51.100.13 tcp dport 5003 dnat to 172.16.0.13:8080
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    # サーバーからclientへの戻りをSNAT（lb経由で戻す）
    oifname "lA" masquerade
    oifname "lB" masquerade
  }
}
NFT

# ===== サーバー: 固有VIP/Portを "signal" でアドバタイズ =====
# 追加サブフローはこの宛先に張りに来る → LBで固定DNATされる
ip netns exec s1 ip mptcp endpoint flush
ip netns exec s2 ip mptcp endpoint flush
ip netns exec s3 ip mptcp endpoint flush
ip netns exec s1 ip mptcp endpoint add ${VIP_S1} dev lo port 5001 signal
ip netns exec s2 ip mptcp endpoint add ${VIP_S2} dev lo port 5002 signal
ip netns exec s3 ip mptcp endpoint add ${VIP_S3} dev lo port 5003 signal

# ===== 確認用HTTPサーバ起動（各サーバで 8080/TCP）=====
for ns in s1 s2 s3; do
  ip netns exec $ns sh -c "printf '%s\n' 'HTTP/1.1 200 OK' 'Connection: close' '' '${ns^^} says hello' | nc -l -p ${BACKEND_PORT} -k >/dev/null 2>&1 &"
done
# ↑ netcat が無い環境は:
# ip netns exec s1 python3 -m http.server 8080 &  …などに置換してOK

echo "=== Ready ==="
echo "clientからのテスト例:"
echo "  ip netns exec client curl -v http://${VIP_SHARED}:443"
echo "  ip netns exec client curl -v http://${VIP_SHARED}:443"
echo "  ip netns exec client curl -v http://${VIP_SHARED}:443"
echo "  # 応答bodyに S1/S2/S3 のどれかが出ます（負荷分散）"
echo
echo "MPTCPのサブフロー確認:"
echo "  ip netns exec client ss -Mpta"
