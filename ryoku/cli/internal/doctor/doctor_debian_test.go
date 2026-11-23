package doctor

import (
	"strings"
	"testing"

	"ryoku-cli/internal/host"
)

func stubDoctorAPT(t *testing.T) {
	t.Helper()
	oldManager := doctorPackageManager
	oldFilteredDNS := doctorFilteredRyokuDNS
	doctorPackageManager = func() (host.PackageManager, error) { return host.APT, nil }
	doctorFilteredRyokuDNS = func(string) bool { return false }
	t.Setenv("RYOKU_HOST_PKGMGR", "apt")
	t.Cleanup(func() {
		doctorPackageManager = oldManager
		doctorFilteredRyokuDNS = oldFilteredDNS
	})
}

func assertNoForeignPackageAdviceDebian(t *testing.T, result recResult) {
	t.Helper()
	text := strings.ToLower(result.detail + " " + result.remedy)
	for _, forbidden := range []string{"pacman", "aur", "limine", "xbps", "dnf"} {
		if strings.Contains(text, forbidden) {
			t.Errorf("Debian result mentions %q: %+v", forbidden, result)
		}
	}
}

func TestDebianUnmanagedBootCheck(t *testing.T) {
	stubDoctorAPT(t)
	res := reconcileBootSpace(true)
	if res.status != recOK {
		t.Fatalf("status = %v, want recOK", res.status)
	}
	if !strings.Contains(res.detail, "Debian") {
		t.Fatalf("detail = %q, want mention of Debian", res.detail)
	}
}

func TestDebianInitramfsChecksDoNotApply(t *testing.T) {
	stubDoctorAPT(t)
	res1 := reconcileInitramfsGPUTrim(true)
	if res1.status != recOK || !strings.Contains(res1.detail, "Debian") {
		t.Fatalf("reconcileInitramfsGPUTrim = %+v, want ok with Debian", res1)
	}
	res2 := reconcileInitramfsConsoleKeys(true)
	if res2.status != recOK || !strings.Contains(res2.detail, "Debian") {
		t.Fatalf("reconcileInitramfsConsoleKeys = %+v, want ok with Debian", res2)
	}
}

func TestDebianPendingConfigCheckName(t *testing.T) {
	stubDoctorAPT(t)
	name := pendingConfigCheckName()
	if name != "pending package config updates" {
		t.Fatalf("pendingConfigCheckName() = %q, want 'pending package config updates'", name)
	}
}
