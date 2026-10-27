package content

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

// RecipesFile is where a pack version keeps the recipe of each of its
// datasets (ADR-007): the datasets themselves stay out of git.
const RecipesFile = "datasets.json"

// Recipe is how cmd/freeze rebuilds one dataset: the flags that froze it.
type Recipe struct {
	ID string `json:"id"`
	// Asset is a catalogue asset; Currency "EUR" converts its closes at ECB rates.
	Asset    string `json:"asset,omitempty"`
	Currency string `json:"currency,omitempty"`
	// FX "USD" is what one dollar was worth in euros.
	FX string `json:"fx,omitempty"`
	// Livret is a Livret A holding of Deposit euros put in on From.
	Livret   bool   `json:"livret,omitempty"`
	Deposit  int64  `json:"deposit,omitempty"`
	Interval string `json:"interval"`
	From     string `json:"from"`
	To       string `json:"to"`
}

// Problem says what keeps cmd/freeze from following the recipe; "" when
// nothing does.
func (r Recipe) Problem() string {
	var problems []string
	add := func(format string, a ...any) { problems = append(problems, fmt.Sprintf(format, a...)) }
	if r.ID == "" {
		add("id is empty")
	}
	kinds := 0
	for _, set := range []bool{r.Asset != "", r.FX != "", r.Livret} {
		if set {
			kinds++
		}
	}
	if kinds != 1 {
		add("one of asset, fx and livret")
	}
	switch {
	case r.Currency != "" && r.Asset == "":
		add("currency goes with asset")
	case r.Currency != "" && r.Currency != "EUR":
		add("currency: only EUR")
	}
	if r.FX != "" && r.FX != "USD" {
		add("fx: only USD")
	}
	switch {
	case r.Livret && r.Deposit <= 0:
		add("deposit is not positive")
	case !r.Livret && r.Deposit != 0:
		add("deposit goes with livret")
	}
	if !slices.Contains(Intervals, r.Interval) {
		add("interval %q is unknown", r.Interval)
	}
	from, fromErr := time.Parse(time.DateOnly, r.From)
	to, toErr := time.Parse(time.DateOnly, r.To)
	if fromErr != nil {
		add("from %q is not a day", r.From)
	}
	if toErr != nil {
		add("to %q is not a day", r.To)
	}
	if fromErr == nil && toErr == nil && from.After(to) {
		add("from %s is after to %s", r.From, r.To)
	}
	return strings.Join(problems, "; ")
}

// ReadRecipes reads the recipes of the pack version in packDir; none when it
// has no recipes file.
func ReadRecipes(packDir string) ([]Recipe, error) {
	raw, err := os.ReadFile(filepath.Join(packDir, RecipesFile))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	var recipes []Recipe
	if err := dec.Decode(&recipes); err != nil {
		return nil, err
	}
	return recipes, nil
}

// WriteRecipe records r in packDir's recipes, in place of the one with its
// id: sorted by id, one per line.
func WriteRecipe(packDir string, r Recipe) error {
	recipes, err := ReadRecipes(packDir)
	if err != nil {
		return err
	}
	recipes = slices.DeleteFunc(recipes, func(old Recipe) bool { return old.ID == r.ID })
	recipes = append(recipes, r)
	slices.SortFunc(recipes, func(a, b Recipe) int { return strings.Compare(a.ID, b.ID) })

	var b bytes.Buffer
	b.WriteString("[\n")
	for i, r := range recipes {
		line, err := json.Marshal(r)
		if err != nil {
			return err
		}
		b.WriteString("  ")
		b.Write(line)
		if i < len(recipes)-1 {
			b.WriteString(",")
		}
		b.WriteString("\n")
	}
	b.WriteString("]\n")
	return os.WriteFile(filepath.Join(packDir, RecipesFile), b.Bytes(), 0o644)
}
