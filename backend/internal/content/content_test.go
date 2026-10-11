package content

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// write lays out files under root: path → content.
func write(t *testing.T, root string, files map[string]string) {
	t.Helper()
	for path, body := range files {
		full := filepath.Join(root, path)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

const (
	island = `{"id": "actions-etf", "version": 2, "title": {"fr": "Actions & ETF", "en": "Stocks & ETFs"},
		"nodes": ["ae.apple", "ae.march"]}`
	apple = `{"id": "ae.apple", "type": "predict_reveal", "status": "published",
		"title": {"fr": "Apple ou ETF Monde ?", "en": "Apple or a world ETF?"},
		"question": {"fr": "Lequel a le plus chuté ?", "en": "Which fell more?"},
		"choices": [{"id": "apple", "label": {"fr": "Apple", "en": "Apple"}}],
		"answer": "apple",
		"datasets": ["ds.aapl"],
		"explanation": {"fr": "C'est la {{diversification}}.", "en": "That's {{diversification}}."},
		"glossary": ["diversification"]}`
	march = `{"id": "ae.march", "type": "decision", "status": "published",
		"title": {"fr": "Mars 2020", "en": "March 2020"},
		"bridge": {"date": "2020-02-18", "difficulty": "realiste"},
		"covers": {"from": "2020-02-01", "to": "2021-02-28"}}`
	aapl = `{"id": "ds.aapl", "source": "twelvedata", "asset": "apple", "adjusted": true,
		"currency": "USD", "interval": "1week", "frozen_at": "2026-10-06",
		"points": [["2022-01-07", 172.170], ["2022-01-14", 173.07]]}`
	diversification = `{"id": "diversification", "status": "published",
		"title": {"fr": "Diversification", "en": "Diversification"},
		"short": {"fr": "Ne pas tout miser sur un seul actif.", "en": "Not betting everything on one asset."},
		"body": {"fr": "Voir aussi la {{volatilite}}.", "en": "See also {{volatilite}}."},
		"related": ["volatilite"]}`
	volatilite = `{"id": "volatilite", "status": "published",
		"title": {"fr": "Volatilité", "en": "Volatility"},
		"short": {"fr": "L'amplitude des variations.", "en": "How much prices swing."},
		"body": {"fr": "…", "en": "…"}}`
)

// pack lays out a valid version 2 of actions-etf, with [changes] on top.
func pack(t *testing.T, changes map[string]string) Ref {
	t.Helper()
	root := t.TempDir()
	files := map[string]string{
		"island.json":                   island,
		"nodes/ae.apple.json":           apple,
		"nodes/ae.march.json":           march,
		"datasets/ds.aapl.json":         aapl,
		"glossary/diversification.json": diversification,
		"glossary/volatilite.json":      volatilite,
	}
	for path, body := range changes {
		files[path] = body
	}
	for path, body := range files {
		if body == "" {
			delete(files, path)
		}
	}
	dir := filepath.Join(root, "packs", "actions-etf", "2")
	write(t, dir, files)
	return Ref{Island: "actions-etf", Version: 2, Dir: dir}
}

// problems reads [ref] and returns its problems, one per line.
func problems(t *testing.T, ref Ref, release bool) string {
	t.Helper()
	_, err := Read(ref, release)
	if err == nil {
		return ""
	}
	return err.Error()
}

func expectProblem(t *testing.T, changes map[string]string, want ...string) {
	t.Helper()
	got := problems(t, pack(t, changes), false)
	for _, w := range want {
		if !strings.Contains(got, w) {
			t.Errorf("want a problem containing %q, got:\n%s", w, got)
		}
	}
}

func TestAValidPack(t *testing.T) {
	p, err := Read(pack(t, nil), true)
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Island   map[string]any   `json:"island"`
		Nodes    []map[string]any `json:"nodes"`
		Datasets []map[string]any `json:"datasets"`
		Glossary []map[string]any `json:"glossary"`
	}
	if err := json.Unmarshal(p.Document(), &doc); err != nil {
		t.Fatal(err)
	}
	if doc.Island["id"] != "actions-etf" || len(doc.Nodes) != 2 || len(doc.Datasets) != 1 || len(doc.Glossary) != 2 {
		t.Fatalf("document: %+v", doc)
	}
	// Nodes in path order, terms by id.
	if doc.Nodes[0]["id"] != "ae.apple" || doc.Glossary[0]["id"] != "diversification" {
		t.Errorf("order: %v %v", doc.Nodes[0]["id"], doc.Glossary[0]["id"])
	}
}

func TestTheDocumentKeepsTextAndDigitsAsWritten(t *testing.T) {
	p, err := Read(pack(t, nil), false)
	if err != nil {
		t.Fatal(err)
	}
	doc := string(p.Document())
	for _, want := range []string{`"Actions & ETF"`, `172.170`, `"C'est la {{diversification}}."`, `"…"`} {
		if !strings.Contains(doc, want) {
			t.Errorf("document lacks %s", want)
		}
	}
	if strings.Contains(doc, "\n") {
		t.Error("the document is one line")
	}
	again, _ := Read(pack(t, nil), false)
	if string(again.Document()) != doc {
		t.Error("the same pack assembles to the same bytes")
	}
}

func TestIsland(t *testing.T) {
	expectProblem(t, map[string]string{"island.json": `{"id": "other", "version": 3, "title": {"fr": "A"}, "nodes": [], "extra": 1}`},
		`island.json: id "other" is not the directory's "actions-etf"`,
		`island.json: version 3 is not the directory's 2`,
		`island.json: title: "en" is missing`,
		`island.json: nodes: the path is empty`,
		`island.json: unknown field "extra"`,
	)
	expectProblem(t, map[string]string{"island.json": `{"id": "actions-etf"`}, "island.json: ")
	expectProblem(t, map[string]string{"island.json": ""}, "island.json: ")
}

func TestThePathAndTheNodeFiles(t *testing.T) {
	expectProblem(t, map[string]string{
		"island.json": `{"id": "actions-etf", "version": 2, "title": {"fr": "A", "en": "A"},
			"nodes": ["ae.apple", "ae.apple", "ae.gone"]}`,
	},
		`island.json: nodes: "ae.apple" is listed twice`,
		`island.json: nodes: "ae.gone" has no file`,
		`nodes/ae.march.json: not on the island's path`,
	)
	expectProblem(t, map[string]string{"nodes/ae.march.json": strings.Replace(march, `"ae.march"`, `"ae.other"`, 1)},
		`nodes/ae.march.json: id "ae.other" is not the file's name`)
}

func TestNodes(t *testing.T) {
	expectProblem(t, map[string]string{"nodes/ae.march.json": `{"id": "ae.march", "type": "quiz", "status": "done",
		"title": {"fr": "Mars", "en": ""},
		"glossary": ["nope"], "datasets": ["ds.nope"],
		"bridge": {"date": "2020-02-30", "difficulty": "facile"},
		"covers": {"from": "2021-01-01", "to": "2020-01-01"}}`},
		`nodes/ae.march.json: type "quiz" is unknown`,
		`nodes/ae.march.json: status "done" is unknown`,
		`nodes/ae.march.json: title: "en" is empty`,
		`nodes/ae.march.json: glossary: "nope" is not a term of the pack`,
		`nodes/ae.march.json: datasets: "ds.nope" is not a dataset of the pack`,
		`nodes/ae.march.json: bridge: date "2020-02-30" is not a day`,
		`nodes/ae.march.json: bridge: difficulty "facile" is unknown`,
		`nodes/ae.march.json: covers: "from" is after "to"`,
	)
	// A null bridge is no bridge.
	if got := problems(t, pack(t, map[string]string{"nodes/ae.march.json": strings.Replace(march,
		`{"date": "2020-02-18", "difficulty": "realiste"}`, `null`, 1)}), false); got != "" {
		t.Errorf("null bridge: %s", got)
	}
}

func TestEveryTextHasBothLanguages(t *testing.T) {
	expectProblem(t, map[string]string{"nodes/ae.apple.json": strings.Replace(apple,
		`{"id": "apple", "label": {"fr": "Apple", "en": "Apple"}}`,
		`{"id": "apple", "label": {"fr": "Apple"}}, {"id": "w", "label": {"fr": "W", "en": "W", "de": "W"}}`, 1)},
		`nodes/ae.apple.json: choices[0].label: "en" is missing`,
		`nodes/ae.apple.json: choices[1].label: "de" is not a language`,
	)
}

func TestTermLinksInTexts(t *testing.T) {
	expectProblem(t, map[string]string{"nodes/ae.apple.json": strings.Replace(apple,
		`"That's {{diversification}}."`, `"That's {{diversity}}."`, 1)},
		`nodes/ae.apple.json: explanation.en: {{diversity}} is not a term of the pack`)
	expectProblem(t, map[string]string{"glossary/volatilite.json": strings.Replace(volatilite,
		`"How much prices swing."`, `"How much {{prices}} swing."`, 1)},
		`glossary/volatilite.json: short.en: {{prices}} is not a term of the pack`)
	// {{term|shown text}}: the text shown in the sentence.
	if got := problems(t, pack(t, map[string]string{"nodes/ae.apple.json": strings.Replace(apple,
		`"C'est la {{diversification}}."`, `"C'est la {{diversification|diversification}}."`, 1)}), false); got != "" {
		t.Errorf("a link with its own text: %s", got)
	}
	expectProblem(t, map[string]string{"nodes/ae.apple.json": strings.Replace(apple,
		`"C'est la {{diversification}}."`, `"C'est la {{diversity|diversification}}."`, 1)},
		`nodes/ae.apple.json: explanation.fr: {{diversity}} is not a term of the pack`)
}

func TestDatasets(t *testing.T) {
	expectProblem(t, map[string]string{"datasets/ds.aapl.json": `{"id": "ds.other", "source": "", "adjusted": "yes",
		"currency": "usd", "interval": "1hour", "frozen_at": "06/10/2026",
		"points": [["2022-01-14", 1], ["2022-01-07", 2], ["2022-01-21"], ["2022-01-28", "3"]]}`},
		`datasets/ds.aapl.json: id "ds.other" is not the file's name`,
		`datasets/ds.aapl.json: source is empty`,
		`datasets/ds.aapl.json: adjusted is not true or false`,
		`datasets/ds.aapl.json: currency "usd" is not a currency code`,
		`datasets/ds.aapl.json: interval "1hour" is unknown`,
		`datasets/ds.aapl.json: frozen_at "06/10/2026" is not a day`,
		`datasets/ds.aapl.json: points[1]: 2022-01-07 does not follow 2022-01-14`,
		`datasets/ds.aapl.json: points[2]: not [day, number]`,
		`datasets/ds.aapl.json: points[3]: not [day, number]`,
	)
	expectProblem(t, map[string]string{"datasets/ds.aapl.json": strings.Replace(aapl,
		`[["2022-01-07", 172.170], ["2022-01-14", 173.07]]`, `[]`, 1)},
		`datasets/ds.aapl.json: points: none`)
}

func TestGlossary(t *testing.T) {
	expectProblem(t, map[string]string{"glossary/volatilite.json": `{"id": "volatility", "status": "draft",
		"title": {"fr": "Volatilité", "en": "Volatility"}, "short": {"fr": "x", "en": "x"},
		"related": ["nope"]}`},
		`glossary/volatilite.json: id "volatility" is not the file's name`,
		`glossary/volatilite.json: body: missing`,
		`glossary/volatilite.json: related: "nope" is not a term of the pack`,
	)
}

func TestARelease_HasNoDraft(t *testing.T) {
	ref := pack(t, map[string]string{
		"nodes/ae.march.json":      strings.Replace(march, `"published"`, `"draft"`, 1),
		"glossary/volatilite.json": strings.Replace(volatilite, `"published"`, `"draft"`, 1),
	})
	if got := problems(t, ref, false); got != "" {
		t.Errorf("drafts are fine while building: %s", got)
	}
	got := problems(t, ref, true)
	for _, want := range []string{"nodes/ae.march.json: a draft", "glossary/volatilite.json: a draft"} {
		if !strings.Contains(got, want) {
			t.Errorf("want %q in:\n%s", want, got)
		}
	}
}

func TestFindListsEveryVersion(t *testing.T) {
	root := t.TempDir()
	write(t, root, map[string]string{
		"packs/actions-etf/1/island.json":  island,
		"packs/actions-etf/10/island.json": island,
		"packs/actions-etf/2/island.json":  island,
		"packs/budget/1/island.json":       island,
	})
	refs, err := Find(root)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, r := range refs {
		got = append(got, r.Island+"/"+filepath.Base(r.Dir))
	}
	if strings.Join(got, " ") != "actions-etf/1 actions-etf/2 actions-etf/10 budget/1" {
		t.Errorf("refs: %v", got)
	}

	write(t, root, map[string]string{"packs/actions-etf/next/island.json": island})
	if _, err := Find(root); err == nil || !strings.Contains(err.Error(), "next") {
		t.Errorf("a version directory that is not a number: %v", err)
	}
	if _, err := Find(filepath.Join(root, "missing")); err == nil {
		t.Error("a missing content directory is an error")
	}
}

func TestTheLibraryPublishesTheLatestRelease(t *testing.T) {
	root := t.TempDir()
	v := func(n string) string { return strings.Replace(island, `"version": 2`, `"version": `+n, 1) }
	base := map[string]string{
		"nodes/ae.apple.json":           apple,
		"nodes/ae.march.json":           march,
		"datasets/ds.aapl.json":         aapl,
		"glossary/diversification.json": diversification,
		"glossary/volatilite.json":      volatilite,
	}
	for version, draft := range map[string]bool{"1": false, "2": false, "3": true} {
		files := map[string]string{"island.json": v(version)}
		for p, b := range base {
			files[p] = b
		}
		if draft {
			files["nodes/ae.march.json"] = strings.Replace(march, `"published"`, `"draft"`, 1)
		}
		write(t, filepath.Join(root, "packs", "actions-etf", version), files)
	}
	lib, errs := Load(root)
	if len(errs) != 1 || !strings.Contains(errs[0].Error(), "actions-etf/3") {
		t.Errorf("version 3 has a draft: %v", errs)
	}
	if m := lib.Manifest(); len(m) != 1 || m[0] != (Latest{IslandID: "actions-etf", Version: 2}) {
		t.Errorf("manifest: %+v", m)
	}
	if _, ok := lib.Document("actions-etf", 1); !ok {
		t.Error("an older release stays available")
	}
	if _, ok := lib.Document("actions-etf", 3); ok {
		t.Error("a draft version is not published")
	}

	empty, errs := Load(filepath.Join(root, "missing"))
	if len(errs) != 1 || len(empty.Manifest()) != 0 {
		t.Errorf("no content: %v %v", errs, empty.Manifest())
	}
}
