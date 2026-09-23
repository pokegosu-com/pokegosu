package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDiscoverReadsTheAPIAddress(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != DiscoveryPath {
			http.NotFound(w, r)
			return
		}
		w.Write([]byte(`{"api_url": "https://abc.supabase.co/"}`))
	}))
	defer srv.Close()

	got, err := Discover(context.Background(), srv.Client(), srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	if got != "https://abc.supabase.co" {
		t.Errorf("api url = %q, want it without the trailing slash", got)
	}
}

func TestDiscoverRefusesWhatIsNotAService(t *testing.T) {
	cases := map[string]http.HandlerFunc{
		"no document":   func(w http.ResponseWriter, r *http.Request) { http.NotFound(w, r) },
		"not JSON":      func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("<html>")) },
		"no api_url":    func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(`{}`)) },
		"not a web URL": func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(`{"api_url": "file:///etc"}`)) },
	}
	for name, handler := range cases {
		srv := httptest.NewServer(handler)
		_, err := Discover(context.Background(), srv.Client(), srv.URL)
		srv.Close()

		if err == nil || !strings.Contains(err.Error(), "does not look like a coder service") {
			t.Errorf("%s: err = %v", name, err)
		}
	}
}
