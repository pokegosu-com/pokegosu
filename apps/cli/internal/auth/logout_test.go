package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/pokegosu-com/pokegosu/apps/cli/internal/config"
)

// enrolledAt writes settings for a machine whose API is at apiURL, and
// returns where they are.
func enrolledAt(t *testing.T, apiURL string) string {
	t.Helper()
	t.Setenv("POKEGOSU_CONFIG_HOME", t.TempDir())
	path, err := config.Save(&config.Config{
		URL:        "https://pokegosu.example",
		APIURL:     apiURL,
		APIKey:     "pgt_secret",
		DeviceID:   "550e8400-e29b-41d4-a716-446655440000",
		DeviceName: "laptop",
	})
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	return path
}

func answering(status int, body string) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(status)
		w.Write([]byte(body))
	}))
}

func TestLogoutRetiresAndDeletesTheSettings(t *testing.T) {
	server := answering(http.StatusOK, `{"device_name":"laptop"}`)
	defer server.Close()
	path := enrolledAt(t, server.URL)

	if err := Logout(context.Background()); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Error("the settings are still there; their id is spent")
	}
}

// Retired in the web first: the key works for nothing, so logging out is
// already done but for the settings.
func TestLogoutDeletesTheSettingsOfAMachineAlreadyRetired(t *testing.T) {
	server := answering(http.StatusUnauthorized,
		`{"error":{"code":"unauthorized","message":"unknown or revoked API key"}}`)
	defer server.Close()
	path := enrolledAt(t, server.URL)

	if err := Logout(context.Background()); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Error("the settings are still there")
	}
}

// While the key may still work, deleting it would leave a machine only the
// web can retire.
func TestLogoutKeepsTheSettingsWhenTheServerDidNotRetire(t *testing.T) {
	for name, server := range map[string]*httptest.Server{
		"gateway": answering(http.StatusUnauthorized, `{"code":401,"message":"Invalid JWT"}`),
		"broken":  answering(http.StatusInternalServerError, `{"error":{"code":"internal_error","message":"no"}}`),
	} {
		path := enrolledAt(t, server.URL)
		err := Logout(context.Background())
		server.Close()
		if err == nil {
			t.Errorf("%s: Logout succeeded", name)
		}
		if _, err := os.Stat(path); err != nil {
			t.Errorf("%s: the settings are gone: %v", name, err)
		}
	}
}

func TestLogoutOfAMachineNeverEnrolledIsNotAnError(t *testing.T) {
	t.Setenv("POKEGOSU_CONFIG_HOME", t.TempDir())
	if err := Logout(context.Background()); err != nil {
		t.Fatalf("Logout: %v", err)
	}
}
