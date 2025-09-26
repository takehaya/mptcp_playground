# mptcp_playground

このリポジトリは、[Go Conference 2025: Goで体感するMultipath TCP ― Go 1.24 時代の MPTCP Listener を理解する](https://gocon.jp/2025/talks/958952/)という発表のフォローアップのためのリポジトリです。

このリポジトリでは、MPTCPを喋るSever/ClientのGoでできたバイナリを併用しつつ、MPTCPの実験をしてみるための情報が含まれています。
ここのsampleを触ることで、なんとなくMPTCPのざっくりとした理解を深めることができます。

`./example` 以下に簡単な例を置いています。
以下にはそれらを動かすための共通の情報が書いてあります。

## 事前準備
- ubuntu2204以降を用意して、その上で動かす様にする。
  - mac環境なら[multipass](https://canonical.com/multipass)を使って建てるのが一番便利です。
- Go 1.24.3 以降を用意して入れる

## MPTCP関連のテストをするためのpkgを入れる
```shell
# pkgを入れておく
sudo apt update
sudo apt install -y iproute2 mptcpize mptcpd tcpdump ncat make

# カーネルの MPTCP を有効化
# 一時的な有効化
sudo sysctl -w net.mptcp.enabled=1
# 確認
cat /proc/sys/net/mptcp/enabled
```

### MPTCPに無事対応できるかどうかの確認
```shell
$ mptcpize run curl check.mptcp.dev
You are using MPTCP.
$ curl check.mptcp.dev
You are not using MPTCP.
```

## MPTCPを喋るGoのバイナリをbuildする
```shell
make build
```
