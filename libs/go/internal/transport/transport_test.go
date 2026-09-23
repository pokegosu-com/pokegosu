package transport

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// The tests here are about the shape of a request and of a failure, not about
// any one endpoint, so they call a function name that does not have to exist.
func client(baseURL string) *Client {
	return &Client{BaseURL: baseURL, APIKey: "pgt_secret"}
}

func post(c *Client, body any) error {
	var out struct{}
	return c.Post(context.Background(), "anything", body, &out)
}

// Go drops Authorization when a redirect crosses hosts, but it does not know
// that x-api-key or apikey are credentials. Following one would hand the
// account key to whoever the redirect names.
func TestRedirectsAreNotFollowed(t *testing.T) {
	var leaked string
	attacker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		leaked = r.Header.Get("x-api-key")
		w.Write([]byte(`{"accepted":1}`))
	}))
	defer attacker.Close()

	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, attacker.URL+"/functions/v1/anything", http.StatusTemporaryRedirect)
	}))
	defer origin.Close()

	err := post(client(origin.URL), map[string]string{})
	if err == nil {
		t.Fatal("Ingest followed a redirect")
	}
	if leaked != "" {
		t.Errorf("the API key reached %s", attacker.URL)
	}
	if !strings.Contains(err.Error(), "redirect") {
		t.Errorf("error = %q, want it to say why", err)
	}
}

// Anything can be listening at the configured address. A 201 that carries no
// token, or no deadline, did not start an enrolment — and treating it as one
// would leave the machine polling something that will never answer.

// The gateway answers before the function does, in its own shape, and its
// "code" is a number in some replies and a string in others. Declaring either
// type made the whole body fail to decode and cost us the message too.
func TestGatewayErrorsKeepTheirMessage(t *testing.T) {
	cases := []string{
		`{"message":"Invalid JWT"}`,
		`{"code":401,"message":"Invalid JWT"}`,
		`{"code":"UNAUTHORIZED_NO_AUTH_HEADER","message":"Invalid JWT"}`,
	}

	for _, body := range cases {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusUnauthorized)
			w.Write([]byte(body))
		}))

		err := post(client(server.URL), map[string]string{})
		serverErr, ok := err.(*Error)
		if !ok {
			t.Fatalf("%s: err = %T, want *Error", body, err)
		}
		if serverErr.Message != "Invalid JWT" {
			t.Errorf("%s: Message = %q, want the gateway's message", body, serverErr.Message)
		}
		// Nothing of ours answered, so no code of ours can be read out of it:
		// a caller asking "did our function refuse the key?" must get no.
		if serverErr.FromServer || CodeIs(err, "unauthorized") {
			t.Errorf("%s: read as one of our own failures", body)
		}
		server.Close()
	}
}

func TestANonJSONFailureStillReports(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		w.Write([]byte("<html>502 Bad Gateway</html>"))
	}))
	defer server.Close()

	err := post(client(server.URL), map[string]string{})
	if err == nil {
		t.Fatal("a 502 was accepted")
	}
	if !strings.Contains(err.Error(), "502") {
		t.Errorf("error = %q, want the status code", err)
	}
}

// A caller supplying a transport is thinking about proxies and timeouts, not
// about Go handing x-api-key to a redirect target.

// A caller supplying a transport is thinking about proxies and timeouts, not
// about Go handing x-api-key to a redirect target.
func TestAnInjectedTransportStillRefusesRedirects(t *testing.T) {
	var leaked string
	attacker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		leaked = r.Header.Get("x-api-key")
		w.Write([]byte(`{"accepted":1}`))
	}))
	defer attacker.Close()

	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, attacker.URL+"/functions/v1/anything", http.StatusTemporaryRedirect)
	}))
	defer origin.Close()

	c := client(origin.URL)
	c.HTTP = &http.Client{} // no CheckRedirect: follows by default

	if err := post(c, map[string]string{}); err == nil {
		t.Fatal("Ingest followed a redirect")
	}
	if leaked != "" {
		t.Errorf("the API key reached %s", attacker.URL)
	}
}
