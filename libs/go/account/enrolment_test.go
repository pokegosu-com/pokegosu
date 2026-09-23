package account

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestStartEnrollmentAsksUnderTheMachinesOwnCode(t *testing.T) {
	var gotKey, gotBody string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get("x-api-key")
		body := make([]byte, r.ContentLength)
		r.Body.Read(body)
		gotBody = string(body)
		w.Write([]byte(`{"claim_token":"pge_token","expires_at":"2026-09-23T10:00:00Z"}`))
	}))
	defer server.Close()

	fresh := New(server.URL)
	started, err := fresh.StartEnrollment(context.Background(), "XPTQ4F2K", "d1", "laptop")
	if err != nil {
		t.Fatalf("StartEnrollment: %v", err)
	}
	if started.ClaimToken != "pge_token" {
		t.Errorf("claim token = %q, want the one the server made", started.ClaimToken)
	}
	if started.ExpiresAt.IsZero() {
		t.Error("the deadline did not come back")
	}
	// This is a call made before there is a key, so it must not invent one.
	if gotKey != "" {
		t.Errorf("x-api-key = %q, want nothing sent", gotKey)
	}
	for _, want := range []string{`"code":"XPTQ4F2K"`, `"device_id":"d1"`, `"device_name":"laptop"`} {
		if !strings.Contains(gotBody, want) {
			t.Errorf("body = %q, want %s", gotBody, want)
		}
	}
}

func TestClaimEnrollmentWaitsUntilSomebodyApproves(t *testing.T) {
	approved := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !approved {
			w.WriteHeader(http.StatusAccepted)
			w.Write([]byte(`{"status":"waiting"}`))
			return
		}
		w.Write([]byte(`{"api_key":"pgt_minted","device_name":"laptop"}`))
	}))
	defer server.Close()

	fresh := New(server.URL)
	claim, err := fresh.ClaimEnrollment(context.Background(), "pge_token")
	if err != nil {
		t.Fatalf("ClaimEnrollment: %v", err)
	}
	if !claim.Waiting || claim.APIKey != "" {
		t.Errorf("claim = %+v, want it still waiting and no key", claim)
	}

	approved = true
	claim, err = fresh.ClaimEnrollment(context.Background(), "pge_token")
	if err != nil {
		t.Fatalf("ClaimEnrollment: %v", err)
	}
	if claim.Waiting {
		t.Error("claim says waiting after the server handed over a key")
	}
	if claim.APIKey != "pgt_minted" || claim.DeviceName != "laptop" {
		t.Errorf("claim = %+v, want the minted key and the approved name", claim)
	}
}

// Go drops Authorization when a redirect crosses hosts, but it does not know
// that x-api-key or apikey are credentials. Following one would hand the
// account key to whoever the redirect names.

// Anything can be listening at the configured address. A 201 that carries no
// token, or no deadline, did not start an enrolment — and treating it as one
// would leave the machine polling something that will never answer.
func TestAForeignSuccessIsNotSuccess(t *testing.T) {
	for _, body := range []string{
		`{}`,
		`null`,
		`{"claim_token":"pge_token"}`,
		`{"expires_at":"2026-09-23T10:00:00Z"}`,
		`{"claim_token":"pge_token","expires_at":"soon"}`,
	} {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte(body))
		}))

		fresh := New(server.URL)
		if _, err := fresh.StartEnrollment(context.Background(), "code", "d1", "laptop"); err == nil {
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

	_, err := New(server.URL).ClaimEnrollment(context.Background(), "pge_token")
	if !DeviceTaken(err) {
		t.Errorf("DeviceTaken() = false for %v", err)
	}
	if !strings.Contains(err.Error(), "another account") {
		t.Errorf("error = %q, want the server's message", err)
	}
}

// The gateway answers before the function does, in its own shape, and its
// "code" is a number in some replies and a string in others. Declaring either
// type made the whole body fail to decode and cost us the message too.
