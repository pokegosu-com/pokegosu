package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/pokegosu-com/pokegosu/libs/go/coder/usage"
)

func client(baseURL string) *Client {
	return &Client{BaseURL: baseURL, APIKey: "pgt_secret"}
}

// enrolReply is what the server says when a code is spent.
func enrolReply(deviceID string) string {
	return `{"api_key":"pgt_minted","device_id":"` + deviceID + `","device_name":"laptop"}`
}

// oneRollup is the smallest thing a machine can send, for the tests that are
// about the transport rather than about the payload.
func oneRollup() []usage.Rollup {
	return []usage.Rollup{{Provider: "claude_code", Tokens: 1}}
}

func TestIngestSendsOnlyTheMachinesKey(t *testing.T) {
	var gotAuth, gotProject, gotKey, gotBody string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("authorization")
		gotProject = r.Header.Get("apikey")
		gotKey = r.Header.Get("x-api-key")
		body := make([]byte, r.ContentLength)
		r.Body.Read(body)
		gotBody = string(body)
		w.Write([]byte(`{"accepted":1}`))
	}))
	defer server.Close()

	if _, err := client(server.URL).Ingest(context.Background(), oneRollup()); err != nil {
		t.Fatalf("Ingest: %v", err)
	}

	// One credential, and it is ours. The project's own key used to ride
	// along because the platform's gateway demanded it; the endpoints that
	// machines call no longer ask.
	if gotKey != "pgt_secret" {
		t.Errorf("x-api-key = %q, want this machine's key", gotKey)
	}
	if gotProject != "" || gotAuth != "" {
		t.Errorf("apikey = %q, authorization = %q, want neither sent", gotProject, gotAuth)
	}
	// Which machine these belong to is the key's business, not the body's.
	if strings.Contains(gotBody, "device_id") {
		t.Errorf("body = %q, want no device id in it", gotBody)
	}
}

func TestEnrolTradesACodeForAKey(t *testing.T) {
	var gotKey, gotBody string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get("x-api-key")
		body := make([]byte, r.ContentLength)
		r.Body.Read(body)
		gotBody = string(body)
		w.Write([]byte(enrolReply("d1")))
	}))
	defer server.Close()

	fresh := &Client{BaseURL: server.URL}
	key, err := fresh.Enrol(context.Background(), "XPTQ-4F2K", "d1", "laptop")
	if err != nil {
		t.Fatalf("Enrol: %v", err)
	}
	if key != "pgt_minted" {
		t.Errorf("key = %q, want the one the server minted", key)
	}
	// This is the call made before there is a key, so it must not invent one.
	if gotKey != "" {
		t.Errorf("x-api-key = %q, want nothing sent", gotKey)
	}
	for _, want := range []string{`"code":"XPTQ-4F2K"`, `"device_id":"d1"`, `"device_name":"laptop"`} {
		if !strings.Contains(gotBody, want) {
			t.Errorf("body = %q, want %s", gotBody, want)
		}
	}
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
		http.Redirect(w, r, attacker.URL+"/functions/v1/ingest", http.StatusTemporaryRedirect)
	}))
	defer origin.Close()

	_, err := client(origin.URL).Ingest(context.Background(), oneRollup())
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

// Anything can be listening at the configured address. A 200 that carries no
// key, or names another machine, did not enrol us — and reporting success
// would write settings that do not work.
func TestAForeignSuccessIsNotSuccess(t *testing.T) {
	for _, body := range []string{
		`{}`,
		`null`,
		`{"api_key":"pgt_minted","device_id":"someone-else"}`,
		`{"device_id":"d1"}`,
	} {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte(body))
		}))

		fresh := &Client{BaseURL: server.URL}
		if _, err := fresh.Enrol(context.Background(), "code", "d1", "laptop"); err == nil {
			t.Errorf("body %s was accepted as an enrolment", body)
		}
		server.Close()
	}
}

func TestErrorFromOurFunctions(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusConflict)
		w.Write([]byte(`{"error":{"code":"device_owned_by_another_account","message":"that device id belongs to another account"}}`))
	}))
	defer server.Close()

	fresh := &Client{BaseURL: server.URL}
	_, err := fresh.Enrol(context.Background(), "code", "d1", "laptop")
	serverErr, ok := err.(*Error)
	if !ok {
		t.Fatalf("err = %T, want *Error", err)
	}
	if !serverErr.DeviceTaken() {
		t.Errorf("DeviceTaken() = false for %+v", serverErr)
	}
	if !strings.Contains(serverErr.Error(), "another account") {
		t.Errorf("Error() = %q, want the server's message", serverErr.Error())
	}
}

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

		_, err := client(server.URL).Ingest(context.Background(), oneRollup())
		serverErr, ok := err.(*Error)
		if !ok {
			t.Fatalf("%s: err = %T, want *Error", body, err)
		}
		if serverErr.Message != "Invalid JWT" {
			t.Errorf("%s: Message = %q, want the gateway's message", body, serverErr.Message)
		}
		// Nothing of ours answered, so the API key was never checked.
		if serverErr.KeyRefused() {
			t.Errorf("%s: KeyRefused() = true, but the request never reached a function", body)
		}
		server.Close()
	}
}

func TestOurUnauthorizedIsAKeyRefusal(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"error":{"code":"unauthorized","message":"unknown or revoked API key"}}`))
	}))
	defer server.Close()

	fresh := &Client{BaseURL: server.URL}
	_, err := fresh.Enrol(context.Background(), "code", "d1", "laptop")
	serverErr, ok := err.(*Error)
	if !ok {
		t.Fatalf("err = %T, want *Error", err)
	}
	if !serverErr.KeyRefused() {
		t.Errorf("KeyRefused() = false for %+v", serverErr)
	}
}

func TestANonJSONFailureStillReports(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		w.Write([]byte("<html>502 Bad Gateway</html>"))
	}))
	defer server.Close()

	_, err := client(server.URL).Ingest(context.Background(), oneRollup())
	if err == nil {
		t.Fatal("a 502 was accepted")
	}
	if !strings.Contains(err.Error(), "502") {
		t.Errorf("error = %q, want the status code", err)
	}
}

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
		http.Redirect(w, r, attacker.URL+"/functions/v1/ingest", http.StatusTemporaryRedirect)
	}))
	defer origin.Close()

	c := client(origin.URL)
	c.HTTP = &http.Client{} // no CheckRedirect: follows by default

	if _, err := c.Ingest(context.Background(), oneRollup()); err == nil {
		t.Fatal("Ingest followed a redirect")
	}
	if leaked != "" {
		t.Errorf("the API key reached %s", attacker.URL)
	}
}
