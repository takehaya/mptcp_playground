package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"time"
)

type Config struct {
	Addr    string
	Msg     string
	Newline bool
	Timeout time.Duration
}

func parseFlags() *Config {
	addr := flag.String("addr", "127.0.0.1:8080", "service address (host:port)")
	msg := flag.String("msg", "", "send this message once and exit; if empty, enter interactive mode")
	newline := flag.Bool("newline", true, "append newline when sending")
	timeout := flag.Duration("timeout", 5*time.Second, "read timeout for single-shot mode (-msg)")
	flag.Parse()
	return &Config{
		Addr:    *addr,
		Msg:     *msg,
		Newline: *newline,
		Timeout: *timeout,
	}
}

func dialWithMPTCP(addr string) (net.Conn, bool, error) {
	d := &net.Dialer{}
	d.SetMultipathTCP(true)

	c, err := d.Dial("tcp", addr)
	if err != nil {
		return nil, false, err
	}

	// MPTCP が実際に有効になっているか確認（カーネル/経路が非対応なら false になり得る）
	if tcp, ok := c.(*net.TCPConn); ok {
		mptcp, err := tcp.MultipathTCP()
		if err != nil {
			_ = c.Close()
			return nil, false, err
		}
		return c, mptcp, nil
	}
	_ = c.Close()
	return nil, false, fmt.Errorf("connection is not *net.TCPConn")
}

// 単発送信（-msg 指定時）。サーバからの応答をタイムアウトまで待って標準出力へ。
func runSingleShot(c net.Conn, payload string, newline bool, timeout time.Duration, out io.Writer) error {
	if newline {
		payload += "\n"
	}
	if _, err := c.Write([]byte(payload)); err != nil {
		return fmt.Errorf("write: %w", err)
	}

	_ = c.SetReadDeadline(time.Now().Add(timeout))
	buf := make([]byte, 64<<10) // 64 KiB
	n, err := c.Read(buf)
	if ne, ok := err.(net.Error); ok && ne.Timeout() {
		fmt.Fprintln(out, "no response within timeout; exiting")
		return nil
	} else if err != nil && err != io.EOF {
		return fmt.Errorf("read: %w", err)
	}
	if n > 0 {
		if _, werr := out.Write(buf[:n]); werr != nil {
			return fmt.Errorf("stdout write: %w", werr)
		}
	}
	return nil
}

func recvLoop(c net.Conn, out io.Writer) {
	r := bufio.NewReader(c)
	buf := make([]byte, 4096)
	for {
		n, err := r.Read(buf)
		if n > 0 {
			_, _ = out.Write([]byte("recv> " + string(buf[:n])))
		}
		if err != nil {
			if err != io.EOF {
				fmt.Fprintln(os.Stderr, "read error:", err)
			}
			return
		}
	}
}

func sendLoop(c net.Conn, in *bufio.Scanner, newline bool) error {
	for in.Scan() {
		line := in.Text()
		if newline {
			line += "\n"
		}
		if _, err := c.Write([]byte(line)); err != nil {
			return fmt.Errorf("write error: %w", err)
		}
	}
	if err := in.Err(); err != nil {
		return fmt.Errorf("stdin error: %w", err)
	}
	return nil
}

func runInteractive(c net.Conn, newline bool) error {
	go recvLoop(c, os.Stdout)

	sc := bufio.NewScanner(os.Stdin)
	// 長文も扱えるように 1MB まで拡張
	sc.Buffer(make([]byte, 0, 1024*1024), 1024*1024)

	if err := sendLoop(c, sc, newline); err != nil {
		return err
	}
	return nil
}

func main() {
	cfg := parseFlags()

	conn, mptcp, err := dialWithMPTCP(cfg.Addr)
	if err != nil {
		panic(err)
	}
	defer conn.Close()

	fmt.Printf("connected to %s with mptcp: %t\n", cfg.Addr, mptcp)

	// 単発送信モード
	if cfg.Msg != "" {
		if err := runSingleShot(conn, cfg.Msg, cfg.Newline, cfg.Timeout, os.Stdout); err != nil {
			panic(err)
		}
		return
	}

	// 対話モード
	fmt.Println("entering interactive mode; type messages and press Enter to send")
	fmt.Println("press Ctrl+D (EOF) to exit")
	fmt.Println("--------------------------------------------------------")
	if err := runInteractive(conn, cfg.Newline); err != nil {
		fmt.Fprintln(os.Stderr, err)
	}
}
