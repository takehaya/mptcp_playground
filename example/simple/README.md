# simple case

[Multipath TCP on RHEL 8: From one to many subflows](https://developers.redhat.com/articles/2021/10/20/multipath-tcp-rhel-8-one-many-subflows#working_with_multiple_paths)を参考に、ubuntu環境で動かせる様にしたものです。

![https://developers.redhat.com/sites/default/files/setup.png](https://developers.redhat.com/sites/default/files/setup.png)

このトポロジーで動作させます。

## 事前準備
```shell
sudo ./topo.sh
```

## 手動での実験の仕方
```shell
# サーバ側で待ち受け（NS内）
sudo ip netns exec mptcp-server mptcpize run \
ncat -k -4 -i 30 -c "sleep 60" -C -o /tmp/server -l 0.0.0.0 4321

# クライアントから1本目経路で接続して送信
sudo ip netns exec mptcp-client mptcpize run \
ncat -c "echo hello world!" 10.0.0.1 4321

# パケットキャプチャ（サーバNSで保存）
sudo ip netns exec mptcp-server tcpdump -i any -w /tmp/mptcp.pcap 'tcp port 4321' -c 50

# mptcpの動作状態が見える
sudo ip netns exec mptcp-client ip mptcp monitor
```

## Goのサーバーを利用した実験の仕方
