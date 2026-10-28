// Command contentcheck validates the content packs under a content directory
// (BRIEF §4.3, §9, ADR-006) and keeps the app's bundled packs in step.
//
//	contentcheck [-release] [-bundle dir [-write]] <content-dir>
//
// Every version of every island is checked. -release also refuses a draft in
// the latest version of each island. -bundle compares <dir>/<island>.json
// with the latest version's document; -write rewrites it instead.
package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"finance-companion/backend/internal/content"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("contentcheck", flag.ContinueOnError)
	flags.SetOutput(stderr)
	release := flags.Bool("release", false, "refuse drafts in the latest version of each island")
	bundle := flags.String("bundle", "", "the app's bundled packs, e.g. ../app/assets/packs")
	write := flags.Bool("write", false, "rewrite the bundled packs instead of comparing them")
	if err := flags.Parse(args); err != nil || flags.NArg() != 1 {
		fmt.Fprintln(stderr, "usage: contentcheck [-release] [-bundle dir [-write]] <content-dir>")
		return 2
	}
	refs, err := content.Find(flags.Arg(0))
	if err != nil {
		fmt.Fprintf(stderr, "contentcheck: %v\n", err)
		return 1
	}

	shared, errs := content.Index(refs)
	for _, err := range errs {
		fmt.Fprintf(stderr, "contentcheck: %v\n", err)
	}
	failed := len(errs) > 0
	report := func(ref content.Ref, err error) {
		failed = true
		for _, line := range strings.Split(err.Error(), "\n") {
			fmt.Fprintf(stderr, "%s/%d: %s\n", ref.Island, ref.Version, line)
		}
	}
	for i, ref := range refs {
		latest := i == len(refs)-1 || refs[i+1].Island != ref.Island
		pack, err := content.Read(ref, *release && latest, shared.TermsBesides(ref.Island))
		if err != nil {
			report(ref, err)
			continue
		}
		fmt.Fprintf(stdout, "contentcheck: %s\n", pack.Stats())
		if !latest || *bundle == "" {
			continue
		}
		path := filepath.Join(*bundle, ref.Island+".json")
		doc := pack.Document()
		if *write {
			if err := os.MkdirAll(*bundle, 0o755); err != nil {
				report(ref, err)
			} else if err := os.WriteFile(path, doc, 0o644); err != nil {
				report(ref, err)
			} else {
				fmt.Fprintf(stdout, "contentcheck: wrote %s\n", path)
			}
			continue
		}
		switch current, err := os.ReadFile(path); {
		case errors.Is(err, os.ErrNotExist):
			report(ref, fmt.Errorf("%s is missing: run contentcheck -bundle %s -write", path, *bundle))
		case err != nil:
			report(ref, err)
		case !bytes.Equal(current, doc):
			report(ref, fmt.Errorf("%s is out of date: run contentcheck -bundle %s -write", path, *bundle))
		}
	}
	if failed {
		return 1
	}
	return 0
}
