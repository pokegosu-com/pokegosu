package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// DiscoveryPath is where a pokegosu service says where its API is.
const DiscoveryPath = "/.well-known/pokegosu.json"

// Discover asks the service a person knows — the web address they sign in
// at — where the API behind it lives. People only ever type that address;
// the API's is the service's business, and it can move without a release.
func Discover(ctx context.Context, client *http.Client, serviceURL string) (string, error) {
	if client == nil {
		client = (&Client{}).http()
	}

	url := serviceURL + DiscoveryPath
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", fmt.Errorf("building the request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("reaching %s: %w", serviceURL, err)
	}
	defer resp.Body.Close()

	notService := fmt.Errorf("%s does not look like a pokegosu service: %s did not describe one", serviceURL, url)
	if resp.StatusCode != http.StatusOK {
		return "", notService
	}

	var doc struct {
		APIURL string `json:"api_url"`
	}
	payload, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return "", fmt.Errorf("reading %s: %w", url, err)
	}
	if json.Unmarshal(payload, &doc) != nil {
		return "", notService
	}

	api := strings.TrimRight(doc.APIURL, "/")
	if !strings.HasPrefix(api, "https://") && !strings.HasPrefix(api, "http://") {
		return "", notService
	}
	return api, nil
}
