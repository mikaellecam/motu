package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const (
	island = `{"id": "actions-etf", "version": %s, "title": {"fr": "Actions & ETF", "en": "Stocks & ETFs"},
		"nodes": ["ae.fees"]}`
	node = `{"id": "ae.fees", "type": "toy", "status": "%s", "title": {"fr": "Les frais", "en": "Fees"}}`
)

// contentDir lays out actions-etf versions 1 (published) and 2 (status of
// its node: [latest]).
func contentDir(t *testing.T, latest string) string {
	t.Helper()
	root := t.TempDir()
	for version, status := range map[string]string{"1": "published", "2": latest} {
		dir := filepath.Join(root, "packs", "actions-etf", version)
		os.MkdirAll(filepath.Join(dir, "nodes"), 0o755)
		os.WriteFile(filepath.Join(dir, "island.json"), []byte(strings.Replace(island, "%s", version, 1)), 0o644)
		os.WriteFile(filepath.Join(dir, "nodes", "ae.fees.json"), []byte(strings.Replace(node, "%s", status, 1)), 0o644)
	}
	return root
}

func check(args ...string) (int, string, string) {
	var out, errs bytes.Buffer
	code := run(args, &out, &errs)
	return code, out.String(), errs.String()
}

func TestEveryVersionIsChecked(t *testing.T) {
	code, out, errs := check(contentDir(t, "draft"))
	if code != 0 || !strings.Contains(out, "actions-etf v1: 1 nodes") || !strings.Contains(out, "actions-etf v2") {
		t.Errorf("exit %d\n%s%s", code, out, errs)
	}
	root := contentDir(t, "published")
	os.WriteFile(filepath.Join(root, "packs", "actions-etf", "1", "island.json"), []byte("{"), 0o644)
	if code, _, errs := check(root); code != 1 || !strings.HasPrefix(errs, "actions-etf/1: island.json: ") {
		t.Errorf("exit %d: %s", code, errs)
	}
}

func TestAReleaseRefusesADraftInTheLatestVersion(t *testing.T) {
	if code, _, errs := check("-release", contentDir(t, "draft")); code != 1 ||
		!strings.Contains(errs, "actions-etf/2: nodes/ae.fees.json: a draft") {
		t.Errorf("exit %d: %s", code, errs)
	}
	if code, _, errs := check("-release", contentDir(t, "published")); code != 0 {
		t.Errorf("exit %d: %s", code, errs)
	}
}

func TestTheBundleFollowsTheLatestVersion(t *testing.T) {
	root := contentDir(t, "draft")
	bundle := t.TempDir()
	if code, _, errs := check("-bundle", bundle, root); code != 1 || !strings.Contains(errs, "actions-etf.json is missing") {
		t.Errorf("no bundle yet: exit %d: %s", code, errs)
	}
	if code, out, errs := check("-bundle", bundle, "-write", root); code != 0 || !strings.Contains(out, "wrote") {
		t.Errorf("write: exit %d: %s", code, errs)
	}
	written, _ := os.ReadFile(filepath.Join(bundle, "actions-etf.json"))
	if !strings.Contains(string(written), `"version":2`) {
		t.Errorf("the latest version is bundled: %s", written)
	}
	if code, _, errs := check("-bundle", bundle, root); code != 0 {
		t.Errorf("in step: exit %d: %s", code, errs)
	}

	os.WriteFile(filepath.Join(root, "packs", "actions-etf", "2", "nodes", "ae.fees.json"),
		[]byte(strings.Replace(strings.Replace(node, "%s", "draft", 1), "Les frais", "Des frais", 1)), 0o644)
	if code, _, errs := check("-bundle", bundle, root); code != 1 || !strings.Contains(errs, "out of date") {
		t.Errorf("source changed: exit %d: %s", code, errs)
	}
}

func TestUsage(t *testing.T) {
	if code, _, _ := check(); code != 2 {
		t.Errorf("no directory: exit %d", code)
	}
	if code, _, errs := check(filepath.Join(t.TempDir(), "missing")); code != 1 || errs == "" {
		t.Errorf("missing directory: exit %d", code)
	}
}
