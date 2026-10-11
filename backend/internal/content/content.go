// Package content reads, checks and assembles the content packs written in
// content/packs/<islandId>/<version>/ (BRIEF §4.3, §9, ADR-006): one source
// tree per version, one JSON document on the wire and in the app's bundle.
package content

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Ref locates one version of an island's pack.
type Ref struct {
	Island  string
	Version int
	Dir     string
}

// Find lists every pack version under contentDir/packs, by island then
// version.
func Find(contentDir string) ([]Ref, error) {
	root := filepath.Join(contentDir, "packs")
	islands, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}
	var refs []Ref
	for _, island := range islands {
		if !island.IsDir() {
			continue
		}
		versions, err := os.ReadDir(filepath.Join(root, island.Name()))
		if err != nil {
			return nil, err
		}
		for _, v := range versions {
			if !v.IsDir() {
				continue
			}
			n, err := strconv.Atoi(v.Name())
			if err != nil || n < 1 {
				return nil, fmt.Errorf("%s/%s: a version directory is a number from 1", island.Name(), v.Name())
			}
			refs = append(refs, Ref{island.Name(), n, filepath.Join(root, island.Name(), v.Name())})
		}
	}
	sort.Slice(refs, func(i, j int) bool {
		if refs[i].Island != refs[j].Island {
			return refs[i].Island < refs[j].Island
		}
		return refs[i].Version < refs[j].Version
	})
	return refs, nil
}

// Pack is a version that passed the checks.
type Pack struct {
	Ref      Ref
	island   object
	nodes    []object
	datasets []object
	glossary []object
}

type object = map[string]any

// Document is the pack as one compact JSON document, `{island, nodes,
// datasets, glossary}`: nodes in path order, datasets and terms by id, keys
// sorted, text and digits as written. The same source gives the same bytes.
func (p *Pack) Document() []byte {
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	enc.Encode(map[string]any{
		"island": p.island, "nodes": p.nodes, "datasets": p.datasets, "glossary": p.glossary,
	})
	return bytes.TrimSuffix(b.Bytes(), []byte("\n"))
}

// Stats is a one-line summary of the pack.
func (p *Pack) Stats() string {
	return fmt.Sprintf("%s v%d: %d nodes, %d datasets, %d terms",
		p.Ref.Island, p.Ref.Version, len(p.nodes), len(p.datasets), len(p.glossary))
}

// Read loads and checks the pack at ref (BRIEF §4.3): the island and its
// path, every node, dataset and glossary term, both languages on every text,
// and every reference to a term or dataset. In a [release], no node or term
// may be a draft (BRIEF §9). Every problem is reported, one per line, each
// prefixed with its file.
func Read(ref Ref, release bool) (*Pack, error) {
	c := checker{release: release}
	island := c.file(ref.Dir, "island.json")
	nodes := c.dir(ref.Dir, "nodes")
	datasets := c.dir(ref.Dir, "datasets")
	glossary := c.dir(ref.Dir, "glossary")
	c.terms = ids(glossary)
	c.datasets = ids(datasets)

	var path []object
	if island != nil {
		path = c.island(island, ref, nodes)
	}
	for _, f := range nodes {
		c.node(f)
	}
	for _, f := range datasets {
		c.dataset(f)
	}
	for _, f := range glossary {
		c.term(f)
	}
	if len(c.problems) > 0 {
		return nil, errors.Join(c.problems...)
	}
	return &Pack{
		Ref:      ref,
		island:   island.body,
		nodes:    path,
		datasets: bodies(datasets),
		glossary: bodies(glossary),
	}, nil
}

// file is one JSON object of the pack; its id is its name without .json.
type file struct {
	name string // relative to the pack
	id   string
	body object
}

func ids(files []file) map[string]bool {
	set := map[string]bool{}
	for _, f := range files {
		set[f.id] = true
	}
	return set
}

func bodies(files []file) []object {
	out := make([]object, len(files))
	for i, f := range files {
		out[i] = f.body
	}
	return out
}

type checker struct {
	release         bool
	terms, datasets map[string]bool
	problems        []error
}

func (c *checker) add(name, format string, args ...any) {
	c.problems = append(c.problems, fmt.Errorf("%s: %s", name, fmt.Sprintf(format, args...)))
}

// file reads name as a JSON object, numbers kept as written; nil when it
// cannot.
func (c *checker) file(dir, name string) *file {
	raw, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		c.add(name, "%v", err)
		return nil
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var body object
	if err := dec.Decode(&body); err != nil {
		c.add(name, "%v", err)
		return nil
	}
	if dec.More() {
		c.add(name, "data after the object")
		return nil
	}
	return &file{name: filepath.ToSlash(name), id: strings.TrimSuffix(filepath.Base(name), ".json"), body: body}
}

// dir reads every .json file of sub, by name; a missing directory is empty.
func (c *checker) dir(packDir, sub string) []file {
	entries, err := os.ReadDir(filepath.Join(packDir, sub))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		c.add(sub, "%v", err)
		return nil
	}
	var files []file
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		if f := c.file(packDir, filepath.Join(sub, e.Name())); f != nil {
			files = append(files, *f)
		}
	}
	return files
}

var islandFields = []string{"id", "version", "title", "nodes"}

// island checks island.json and returns the nodes of its path, in order.
func (c *checker) island(f *file, ref Ref, nodes []file) []object {
	b := f.body
	for key := range b {
		if !slices.Contains(islandFields, key) {
			c.add(f.name, "unknown field %q", key)
		}
	}
	if id, _ := b["id"].(string); id != ref.Island {
		c.add(f.name, "id %q is not the directory's %q", id, ref.Island)
	}
	if v, _ := b["version"].(json.Number); v.String() != strconv.Itoa(ref.Version) {
		c.add(f.name, "version %s is not the directory's %d", v, ref.Version)
	}
	c.requireText(f.name, b, "title")
	c.texts(f.name, "", b)

	byID := map[string]object{}
	for _, n := range nodes {
		byID[n.id] = n.body
	}
	listed, ok := b["nodes"].([]any)
	if !ok || len(listed) == 0 {
		c.add(f.name, "nodes: the path is empty")
	}
	var path []object
	seen := map[string]bool{}
	for _, item := range listed {
		id, _ := item.(string)
		switch {
		case seen[id]:
			c.add(f.name, "nodes: %q is listed twice", id)
		case byID[id] == nil:
			c.add(f.name, "nodes: %q has no file", id)
		default:
			path = append(path, byID[id])
		}
		seen[id] = true
	}
	for _, n := range nodes {
		if !seen[n.id] {
			c.add(n.name, "not on the island's path")
		}
	}
	return path
}

// The app's node types and trip difficulties (app/lib/domain).
var (
	nodeTypes    = []string{"predict_reveal", "toy", "decision", "sort", "build_puzzle", "mission", "checkpoint"}
	difficulties = []string{"decouverte", "realiste", "serre", "sur-mesure"}
)

func (c *checker) node(f file) {
	b := f.body
	c.sameID(f)
	if t, _ := b["type"].(string); !slices.Contains(nodeTypes, t) {
		c.add(f.name, "type %q is unknown", t)
	}
	c.status(f)
	c.requireText(f.name, b, "title")
	c.refs(f.name, b, "glossary", c.terms, "a term")
	c.refs(f.name, b, "datasets", c.datasets, "a dataset")
	switch bridge := b["bridge"].(type) {
	case nil:
	case object:
		if d, _ := bridge["date"].(string); !isDay(d) {
			c.add(f.name, "bridge: date %q is not a day", d)
		}
		if d, ok := bridge["difficulty"]; ok {
			if s, _ := d.(string); !slices.Contains(difficulties, s) {
				c.add(f.name, "bridge: difficulty %q is unknown", s)
			}
		}
	default:
		c.add(f.name, "bridge: not an object")
	}
	if covers, ok := b["covers"]; ok {
		period, _ := covers.(object)
		from, _ := period["from"].(string)
		to, _ := period["to"].(string)
		switch {
		case !isDay(from) || !isDay(to):
			c.add(f.name, "covers: \"from\" and \"to\" are days")
		case from > to:
			c.add(f.name, "covers: \"from\" is after \"to\"")
		}
	}
	c.texts(f.name, "", b)
}

var currency = regexp.MustCompile(`^[A-Z]{3}$`)

// Intervals freeze writes.
var Intervals = []string{"1day", "1week", "1month"}

func (c *checker) dataset(f file) {
	b := f.body
	c.sameID(f)
	if s, _ := b["source"].(string); s == "" {
		c.add(f.name, "source is empty")
	}
	if _, ok := b["adjusted"].(bool); !ok {
		c.add(f.name, "adjusted is not true or false")
	}
	if s, _ := b["currency"].(string); !currency.MatchString(s) {
		c.add(f.name, "currency %q is not a currency code", s)
	}
	if s, _ := b["interval"].(string); !slices.Contains(Intervals, s) {
		c.add(f.name, "interval %q is unknown", s)
	}
	if s, _ := b["frozen_at"].(string); !isDay(s) {
		c.add(f.name, "frozen_at %q is not a day", s)
	}
	points, _ := b["points"].([]any)
	if len(points) == 0 {
		c.add(f.name, "points: none")
	}
	previous := ""
	for i, p := range points {
		pair, _ := p.([]any)
		var day string
		var number bool
		if len(pair) == 2 {
			day, _ = pair[0].(string)
			_, number = pair[1].(json.Number)
		}
		if !isDay(day) || !number {
			c.add(f.name, "points[%d]: not [day, number]", i)
			continue
		}
		if previous != "" && day <= previous {
			c.add(f.name, "points[%d]: %s does not follow %s", i, day, previous)
		}
		previous = day
	}
}

func (c *checker) term(f file) {
	b := f.body
	c.sameID(f)
	c.status(f)
	for _, key := range []string{"title", "short", "body"} {
		c.requireText(f.name, b, key)
	}
	c.refs(f.name, b, "related", c.terms, "a term")
	c.texts(f.name, "", b)
}

func (c *checker) sameID(f file) {
	if id, _ := f.body["id"].(string); id != f.id {
		c.add(f.name, "id %q is not the file's name", id)
	}
}

// status: lesson text stays a draft until validated (BRIEF §9).
func (c *checker) status(f file) {
	switch s, _ := f.body["status"].(string); s {
	case "published":
	case "draft":
		if c.release {
			c.add(f.name, "a draft")
		}
	default:
		c.add(f.name, "status %q is unknown", s)
	}
}

// refs checks an optional list of ids against known.
func (c *checker) refs(name string, b object, key string, known map[string]bool, what string) {
	v, ok := b[key]
	if !ok {
		return
	}
	list, ok := v.([]any)
	if !ok {
		c.add(name, "%s: not a list of ids", key)
		return
	}
	for _, item := range list {
		if id, _ := item.(string); !known[id] {
			c.add(name, "%s: %q is not %s of the pack", key, id, what)
		}
	}
}

// requireText reports a missing text; texts checks its languages.
func (c *checker) requireText(name string, b object, key string) {
	v, ok := b[key]
	if !ok {
		c.add(name, "%s: missing", key)
		return
	}
	if !isText(v) {
		c.add(name, "%s: not a text in fr and en", key)
	}
}

func isText(v any) bool {
	o, ok := v.(object)
	if !ok {
		return false
	}
	_, fr := o["fr"]
	_, en := o["en"]
	return fr || en
}

var termLink = regexp.MustCompile(`\{\{\s*([^{}]*?)\s*\}\}`)

// texts walks v: every text has a non-empty "fr" and "en" and nothing else,
// and every {{term}} names a term of the pack (BRIEF §4.3).
func (c *checker) texts(name, path string, v any) {
	join := func(key string) string {
		if path == "" {
			return key
		}
		return path + "." + key
	}
	switch v := v.(type) {
	case object:
		if isText(v) {
			for _, lang := range []string{"fr", "en"} {
				switch s, ok := v[lang]; {
				case !ok:
					c.add(name, "%s: %q is missing", path, lang)
				case s == "" || s == nil:
					c.add(name, "%s: %q is empty", path, lang)
				}
			}
			for _, key := range sortedKeys(v) {
				if key != "fr" && key != "en" {
					c.add(name, "%s: %q is not a language", path, key)
				}
			}
		}
		for _, key := range sortedKeys(v) {
			c.texts(name, join(key), v[key])
		}
	case []any:
		for i, item := range v {
			c.texts(name, fmt.Sprintf("%s[%d]", path, i), item)
		}
	case string:
		for _, m := range termLink.FindAllStringSubmatch(v, -1) {
			if !c.terms[m[1]] {
				c.add(name, "%s: {{%s}} is not a term of the pack", path, m[1])
			}
		}
	}
}

func sortedKeys(o object) []string {
	keys := make([]string, 0, len(o))
	for k := range o {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func isDay(s string) bool {
	_, err := time.Parse(time.DateOnly, s)
	return err == nil
}

// Library holds what the server publishes: for each island, the versions
// that pass the release check.
type Library struct {
	docs map[string]map[int][]byte
}

// Latest is one row of the manifest.
type Latest struct {
	IslandID string `json:"islandId"`
	Version  int    `json:"version"`
}

// Load reads every pack version under contentDir as a release. A version
// with a problem is left out and reported; so is a missing directory.
func Load(contentDir string) (*Library, []error) {
	lib := &Library{docs: map[string]map[int][]byte{}}
	refs, err := Find(contentDir)
	if err != nil {
		return lib, []error{err}
	}
	var errs []error
	for _, ref := range refs {
		p, err := Read(ref, true)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s/%d: %w", ref.Island, ref.Version, err))
			continue
		}
		if lib.docs[ref.Island] == nil {
			lib.docs[ref.Island] = map[int][]byte{}
		}
		lib.docs[ref.Island][ref.Version] = p.Document()
	}
	return lib, errs
}

// Manifest is the highest published version of each island, by island.
func (l *Library) Manifest() []Latest {
	out := []Latest{}
	for island, versions := range l.docs {
		latest := 0
		for v := range versions {
			latest = max(latest, v)
		}
		out = append(out, Latest{island, latest})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].IslandID < out[j].IslandID })
	return out
}

// Document is a published version's document.
func (l *Library) Document(island string, version int) ([]byte, bool) {
	doc, ok := l.docs[island][version]
	return doc, ok
}
