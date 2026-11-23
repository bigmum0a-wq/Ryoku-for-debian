package host

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func debianPackageFixture(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "debian.tsv")
	body := "arch\tdebian\tlanes\tnotes\nfd\tfd-find\tdesktop\t\ngithub-cli\tgh\tdesktop\t\nmatugen\tryoku-matugen\tdesktop\tRyoku-owned Debian package.\nmissing\t-\tdesktop\tNot packaged for Debian.\n"
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestAPTDetectionRequiresAptAndDpkg(t *testing.T) {
	tests := []struct {
		name  string
		paths map[string]bool
		want  bool
	}{
		{name: "both", paths: map[string]bool{"apt-get": true, "dpkg-query": true}, want: true},
		{name: "apt-only", paths: map[string]bool{"apt-get": true}, want: false},
		{name: "dpkg-only", paths: map[string]bool{"dpkg-query": true}, want: false},
		{name: "neither", paths: map[string]bool{}, want: false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			runner := &fakeRunner{paths: tc.paths}
			app, _, _ := testApp(runner, nil)
			mgr, err := app.PackageManager()
			if tc.want {
				if err != nil || mgr != APT {
					t.Fatalf("PackageManager() = (%v, %v), want (apt, nil)", mgr, err)
				}
			} else {
				if err == nil && mgr == APT {
					t.Fatalf("PackageManager() unexpectedly returned apt")
				}
			}
		})
	}
}

func TestAPTPackageCommands(t *testing.T) {
	table := debianPackageFixture(t)
	installed := map[string]bool{}

	runner := &fakeRunner{
		paths: map[string]bool{"apt-get": true, "dpkg-query": true, "apt-cache": true, "apt-mark": true, "dpkg": true},
		answer: func(command Command) Result {
			line := argv(command)
			if strings.HasPrefix(line, "apt-get install ") {
				for _, arg := range command.Args[2:] {
					if !strings.HasPrefix(arg, "-") {
						installed[arg] = true
					}
				}
				return Result{}
			}
			if strings.HasPrefix(line, "apt-get remove ") {
				for _, arg := range command.Args[2:] {
					if !strings.HasPrefix(arg, "-") {
						delete(installed, arg)
					}
				}
				return Result{}
			}
			if strings.HasPrefix(line, "apt-mark manual ") {
				return Result{}
			}
			if strings.HasPrefix(line, "dpkg-query -W -f=${Status}") {
				pkg := command.Args[len(command.Args)-1]
				if installed[pkg] {
					return Result{Output: "install ok installed\n"}
				}
				return Result{Code: 1, Output: "unknown ok not-installed\n"}
			}
			if strings.HasPrefix(line, "apt-cache policy") {
				pkg := command.Args[len(command.Args)-1]
				if pkg == "fd-find" || pkg == "gh" || pkg == "ryoku-matugen" {
					return Result{Output: "fd-find:\n  Installed: (none)\n  Candidate: 9.0.0-1\n  Version table:\n"}
				}
				return Result{Code: 1, Output: "N: Unable to locate package " + pkg + "\n"}
			}
			if strings.HasPrefix(line, "dpkg-query -W -f=${Version}") {
				return Result{Output: "9.0.0-1\n"}
			}
			if strings.HasPrefix(line, "dpkg-query -S") {
				return Result{Output: "fd-find: /usr/bin/fdfind\n"}
			}
			if line == "dpkg-query -W -f=${Package}\n" {
				return Result{Output: "pkg1\npkg2\npkg3\n"}
			}
			return Result{}
		},
	}

	env := map[string]string{"RYOKU_HOST_PKGMGR": "apt", "RYOKU_HOST_PKG_TABLE": table}
	app, stdout, stderr := testApp(runner, env)

	// Test local translation
	stdout.Reset()
	if code := app.Execute([]string{"pkg", "local", "fd", "github-cli"}); code != ExitOK {
		t.Fatalf("local exit = %d, stderr = %s", code, stderr.String())
	}
	if got := strings.TrimSpace(stdout.String()); got != "fd-find\ngh" {
		t.Fatalf("local = %q, want \"fd-find\\ngh\"", got)
	}

	// Test available
	if code := app.Execute([]string{"pkg", "available", "fd"}); code != ExitOK {
		t.Fatalf("available fd exit = %d", code)
	}

	// Test not installed yet
	if code := app.Execute([]string{"pkg", "installed", "fd"}); code != ExitFalse {
		t.Fatalf("installed before install exit = %d, want ExitFalse", code)
	}

	// Test install
	if code := app.Execute([]string{"pkg", "install", "fd"}); code != ExitOK {
		t.Fatalf("install fd exit = %d", code)
	}

	// Test installed after install
	if code := app.Execute([]string{"pkg", "installed", "fd"}); code != ExitOK {
		t.Fatalf("installed after install exit = %d, want ExitOK", code)
	}

	// Test version
	stdout.Reset()
	if code := app.Execute([]string{"pkg", "version", "fd"}); code != ExitOK {
		t.Fatalf("version exit = %d", code)
	}
	if got := strings.TrimSpace(stdout.String()); got != "9.0.0-1" {
		t.Fatalf("version = %q, want \"9.0.0-1\"", got)
	}

	// Test owner
	stdout.Reset()
	if code := app.Execute([]string{"pkg", "owner", "/usr/bin/fdfind"}); code != ExitOK {
		t.Fatalf("owner exit = %d", code)
	}
	if got := strings.TrimSpace(stdout.String()); got != "fd-find" {
		t.Fatalf("owner = %q, want \"fd-find\"", got)
	}

	// Test count
	stdout.Reset()
	if code := app.Execute([]string{"pkg", "count"}); code != ExitOK {
		t.Fatalf("count exit = %d", code)
	}
	if got := strings.TrimSpace(stdout.String()); got != "3" {
		t.Fatalf("count = %q, want \"3\"", got)
	}

	// Test explicit mark
	if code := app.Execute([]string{"pkg", "explicit", "fd"}); code != ExitOK {
		t.Fatalf("explicit exit = %d", code)
	}

	// Test remove
	if code := app.Execute([]string{"pkg", "remove", "fd"}); code != ExitOK {
		t.Fatalf("remove exit = %d", code)
	}
	if installed["fd-find"] {
		t.Fatalf("fd-find still marked installed after remove")
	}
}

func TestAPTPackageWhyAndTableFallback(t *testing.T) {
	table := debianPackageFixture(t)
	runner := &fakeRunner{paths: map[string]bool{"apt-get": true, "dpkg-query": true}}
	app, stdout, _ := testApp(runner, map[string]string{
		"RYOKU_HOST_PKGMGR":    "apt",
		"RYOKU_HOST_PKG_TABLE": table,
	})

	stdout.Reset()
	if code := app.Execute([]string{"pkg", "why", "missing"}); code != ExitOK {
		t.Fatalf("why exit = %d", code)
	}
	if got := strings.TrimSpace(stdout.String()); got != "Not packaged for Debian." {
		t.Fatalf("why = %q, want \"Not packaged for Debian.\"", got)
	}

	// Available for missing package returns ExitNotProvided
	if code := app.Execute([]string{"pkg", "available", "missing"}); code != ExitNotProvided {
		t.Fatalf("available missing exit = %d, want ExitNotProvided", code)
	}
}

func TestAPTOrphansParsesAutoremovePlan(t *testing.T) {
	autoremoveOutput := `Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
The following packages will be REMOVED:
  libfoo1 libbar2 orphan3*
0 upgraded, 0 newly installed, 3 to remove and 0 not upgraded.
`
	runner := &fakeRunner{
		paths: map[string]bool{"apt-get": true, "dpkg-query": true},
		answer: func(command Command) Result {
			if strings.Contains(argv(command), "autoremove") {
				return Result{Output: autoremoveOutput}
			}
			return Result{}
		},
	}
	app, _, _ := testApp(runner, map[string]string{"RYOKU_HOST_PKGMGR": "apt"})
	orphans, err := app.Orphans()
	if err != nil {
		t.Fatalf("Orphans() error = %v", err)
	}
	want := []string{"libbar2", "libfoo1", "orphan3"}
	if strings.Join(orphans, " ") != strings.Join(want, " ") {
		t.Fatalf("orphans = %v, want %v", orphans, want)
	}
}

func TestAPTInstallAdvice(t *testing.T) {
	table := debianPackageFixture(t)
	runner := &fakeRunner{paths: map[string]bool{"apt-get": true, "dpkg-query": true}}
	app, _, _ := testApp(runner, map[string]string{
		"RYOKU_HOST_PKGMGR":    "apt",
		"RYOKU_HOST_PKG_TABLE": table,
	})

	advice := app.InstallAdvice("fd", "github-cli", "missing")
	want := "sudo apt-get install fd-find gh; missing is not packaged for this system"
	if advice != want {
		t.Fatalf("advice = %q, want %q", advice, want)
	}
}

func TestDebianTranslationsFileParsesCleanly(t *testing.T) {
	path := "../../../../debian/packages/translations.tsv"
	translations, err := ReadPackageTranslations(path, "debian")
	if err != nil {
		t.Fatalf("ReadPackageTranslations() failed: %v", err)
	}
	if len(translations) != 311 {
		t.Fatalf("len(translations) = %d, want 311", len(translations))
	}
	// Check key package
	fd, ok := translations["fd"]
	if !ok || len(fd.Names) != 1 || fd.Names[0] != "fd-find" {
		t.Fatalf("translations[\"fd\"] = %+v, want fd-find", fd)
	}
}
