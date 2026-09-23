package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
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

// A machine that is told to wait forever is a machine nobody will notice has
// stopped. The deadline the server gave is the end of it.
func TestWaitGivesUpWhenTheRequestRunsOut(t *testing.T) {
	asked := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		asked++
		w.WriteHeader(http.StatusAccepted)
		w.Write([]byte(`{"status":"waiting"}`))
	}))
	defer server.Close()

	pollInterval = time.Millisecond
	defer func() { pollInterval = 2 * time.Second }()

	_, err := New(server.URL).Wait(
		context.Background(),
		Begun{claimToken: "pge_token", ExpiresAt: time.Now().Add(5 * time.Millisecond)},
	)
	if err == nil {
		t.Fatal("Wait returned without a key and without an error")
	}
	if !strings.Contains(err.Error(), "in time") {
		t.Errorf("error = %q, want it to say the request ran out", err)
	}
	if asked == 0 {
		t.Error("Wait never asked")
	}
}

func TestWaitStopsAsWellAsAsking(t *testing.T) {
	approved := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !approved {
			approved = true
			w.WriteHeader(http.StatusAccepted)
			w.Write([]byte(`{"status":"waiting"}`))
			return
		}
		w.Write([]byte(`{"api_key":"pgt_minted","device_name":"laptop"}`))
	}))
	defer server.Close()

	pollInterval = time.Millisecond
	defer func() { pollInterval = 2 * time.Second }()

	claim, err := New(server.URL).Wait(
		context.Background(),
		Begun{claimToken: "pge_token", ExpiresAt: time.Now().Add(time.Minute)},
	)
	if err != nil {
		t.Fatalf("Wait: %v", err)
	}
	if claim.APIKey != "pgt_minted" {
		t.Errorf("key = %q, want the one the server handed over", claim.APIKey)
	}
}

// A code another machine is waiting on is not a failure: the machine draws
// another and asks again, which is why nobody has to think about collisions.
func TestBeginDrawsAgainWhenACodeIsTaken(t *testing.T) {
	var codes []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body := make([]byte, r.ContentLength)
		r.Body.Read(body)
		codes = append(codes, string(body))

		if len(codes) < 3 {
			w.WriteHeader(http.StatusConflict)
			w.Write([]byte(`{"error":{"code":"enrollment_code_taken","message":"that code is in use"}}`))
			return
		}
		w.Write([]byte(`{"claim_token":"pge_token","expires_at":"2026-09-23T10:00:00Z"}`))
	}))
	defer server.Close()

	begun, err := New(server.URL).Begin(
		context.Background(),
		Service{AccountURL: "https://account.example.com"},
		"11111111-1111-4111-8111-111111111111", "laptop")
	if err != nil {
		t.Fatalf("Begin: %v", err)
	}
	if len(codes) != 3 {
		t.Errorf("asked %d times, want it to have drawn again twice", len(codes))
	}
	if codes[0] == codes[1] {
		t.Error("drew the same code again")
	}

	// What the person is told to open, and what they will compare against.
	if want := "https://account.example.com/devices/add/" + begun.Code; begun.ApproveURL != want {
		t.Errorf("ApproveURL = %q, want %q", begun.ApproveURL, want)
	}
	if len(begun.Code) != codeLength+1 {
		t.Errorf("Code = %q, want it split in half", begun.Code)
	}
}

// Past three, something is wrong that drawing again will not fix.
func TestBeginGivesUpOnCollisions(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusConflict)
		w.Write([]byte(`{"error":{"code":"enrollment_code_taken","message":"that code is in use"}}`))
	}))
	defer server.Close()

	_, err := New(server.URL).Begin(context.Background(), Service{}, "d1", "laptop")
	if err == nil {
		t.Fatal("Begin kept drawing for ever")
	}
}
