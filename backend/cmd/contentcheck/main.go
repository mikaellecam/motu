// Command contentcheck validates the content packs under a content directory.
// Pack validation is not implemented yet: it only checks that the directory exists, so CI already runs it.
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: contentcheck <content-dir>")
		os.Exit(2)
	}
	if info, err := os.Stat(os.Args[1]); err != nil || !info.IsDir() {
		fmt.Fprintf(os.Stderr, "contentcheck: %s is not a directory\n", os.Args[1])
		os.Exit(1)
	}
	fmt.Println("contentcheck: no packs to validate yet")
}
