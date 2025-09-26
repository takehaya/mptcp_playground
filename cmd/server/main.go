package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
)

var (
	addr = flag.String("addr", ":8080", "service address")
)

func main() {
	flag.Parse()
	lc := &net.ListenConfig{}
	if !lc.MultipathTCP() {
		panic("MultipathTCP should be off by default")
	}
	ln, err := lc.Listen(context.Background(), "tcp", *addr) // Normal tcp listening
	if err != nil {
		panic(err)
	}
	defer ln.Close()
	fmt.Printf("listening on %s with mptcp: %t\n", *addr, lc.MultipathTCP())
	for {
		conn, err := ln.Accept()
		if err != nil {
			panic(err)
		}
		go func() {
			defer conn.Close()
			isMultipathTCP, err := conn.(*net.TCPConn).MultipathTCP() // Check if the connection supports mptcp
			fmt.Printf("accepted connection from %s with mptcp: %t, err: %v\n", conn.RemoteAddr(), isMultipathTCP, err)
			for {
				buf := make([]byte, 1024)
				n, err := conn.Read(buf)
				if err != nil {
					if errors.Is(err, io.EOF) {
						return
					}
					panic(err)
				}
				fmt.Println("read", n, "bytes", "show msg:", string(buf[:n]))
				if _, err := conn.Write(buf[:n]); err != nil {
					panic(err)
				}
			}
		}()
	}
}
