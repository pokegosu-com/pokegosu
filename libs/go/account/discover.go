package account

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// DiscoveryPath is where a deployment says what it is made of.
const DiscoveryPath = "/.well-known/pokegosu.json"

// Service is what a deployment says about itself.
type Service struct {
	// APIURL is where the Edge Functions are, without a trailing slash.
	APIURL string

	// AccountURL is where a person signs in and approves a machine. login
	// prints it, so nobody is left looking for it.
	AccountURL string
}

// Discover asks the deployment a person knows — the address they were given,
// or the default — what it is made of. People only ever type that address;
// where its parts live is the deployment's business, and they can move
// without a CLI release.
func Discover(ctx context.Context, client *http.Client, serviceURL string) (Service, error) {
	if client == nil {
		client = http.DefaultClient
	}

	url := serviceURL + DiscoveryPath
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return Service{}, fmt.Errorf("building the request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return Service{}, fmt.Errorf("reaching %s: %w", serviceURL, err)
	}
	defer resp.Body.Close()

	notService := fmt.Errorf("%s does not look like a pokegosu service: %s did not describe one", serviceURL, url)
	if resp.StatusCode != http.StatusOK {
		return Service{}, notService
	}

	var doc struct {
		APIURL     string `json:"api_url"`
		AccountURL string `json:"account_url"`
	}
	payload, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return Service{}, fmt.Errorf("reading %s: %w", url, err)
	}
	if json.Unmarshal(payload, &doc) != nil {
		return Service{}, notService
	}

	service := Service{
		APIURL:     strings.TrimRight(doc.APIURL, "/"),
		AccountURL: strings.TrimRight(doc.AccountURL, "/"),
	}
	if !isWebURL(service.APIURL) || !isWebURL(service.AccountURL) {
		return Service{}, notService
	}
	return service, nil
}

func isWebURL(value string) bool {
	return strings.HasPrefix(value, "https://") || strings.HasPrefix(value, "http://")
}
