package host

import (
	"fmt"
	"sort"
	"strings"
)

const debianPackageTable = "/usr/share/ryoku/packages/debian.tsv"

func (a *App) debianTablePath() string {
	if override := a.getenv("RYOKU_HOST_PKG_TABLE"); override != "" {
		return override
	}
	return debianPackageTable
}

func (a *App) debianTable() (packageTable, error) {
	table, err := a.packageTable(a.debianTablePath(), "debian")
	if err != nil {
		return nil, err
	}
	return a.withOverlay(table, "debian")
}

func (a *App) aptPackageWhy(name string) int {
	table, err := a.debianTable()
	if err != nil {
		return a.failf("%v", err)
	}
	return a.packageWhy(table, name, "Not packaged for Debian.")
}

func (a *App) apt(args []string) int {
	if len(args) == 0 {
		return ExitUsage
	}
	verb, rest := args[0], args[1:]
	switch verb {
	case "count":
		if len(rest) > 1 || len(rest) == 1 && rest[0] != "--foreign" {
			return ExitUsage
		}
		return a.aptCount(len(rest) == 1)
	case "install-file":
		if len(rest) == 0 {
			return ExitUsage
		}
		return commandExit(a.run("apt-get", append([]string{"install", "-y"}, rest...)...))
	case "owner":
		if len(rest) != 1 {
			return ExitUsage
		}
		result := a.query("dpkg-query", "-S", rest[0])
		if result.Code != 0 {
			return ExitFalse
		}
		line := strings.TrimSpace(result.Output)
		if pkg, _, ok := strings.Cut(line, ":"); ok {
			line = pkg
		}
		fmt.Fprintln(a.cfg.Stdout, strings.TrimSpace(line))
		return ExitOK
	case "installed", "available", "remove", "local", "explicit":
		if len(rest) == 0 {
			return ExitUsage
		}
	case "version":
		if len(rest) != 1 {
			return ExitUsage
		}
	case "install":
	default:
		return ExitUsage
	}

	upgrade := false
	if verb == "install" {
		for len(rest) > 0 && strings.HasPrefix(rest[0], "--") {
			switch rest[0] {
			case "--upgrade":
				upgrade = true
				rest = rest[1:]
			case "--aur":
				rest = rest[1:]
			case "--overwrite":
				if len(rest) < 2 {
					return ExitUsage
				}
				rest = rest[2:]
			default:
				return ExitUsage
			}
		}
		if len(rest) == 0 {
			return ExitUsage
		}
	}
	if verb == "available" && rest[0] == "--aur" {
		rest = rest[1:]
		if len(rest) == 0 {
			return ExitUsage
		}
	}

	table, err := a.debianTable()
	if err != nil {
		return a.failf("read Debian package table: %v", err)
	}
	if verb == "local" {
		for _, name := range rest {
			mapping := translatePackage(table, name)
			fmt.Fprintln(a.cfg.Stdout, strings.Join(mapping.Names, " "))
		}
		return ExitOK
	}
	translated, unavailable := translatePackages(table, rest)
	if len(unavailable) > 0 {
		if verb == "installed" || verb == "version" {
			return ExitFalse
		}
		if verb == "available" {
			return ExitNotProvided
		}
		a.reportUnavailablePackages(table, unavailable)
		return ExitNotProvided
	}

	switch verb {
	case "installed":
		for _, name := range translated {
			if !a.aptPackageInstalled(name) {
				return ExitFalse
			}
		}
		return ExitOK
	case "available":
		for _, name := range translated {
			if !a.aptPackageAvailable(name) {
				return ExitFalse
			}
		}
		return ExitOK
	case "version":
		result := a.query("dpkg-query", "-W", "-f=${Version}\n", translated[0])
		if result.Code != 0 {
			return ExitFalse
		}
		fmt.Fprintln(a.cfg.Stdout, strings.TrimSpace(result.Output))
		return ExitOK
	case "install":
		command := []string{"install", "-y", "--no-install-recommends"}
		if upgrade {
			command = append(command, "--only-upgrade")
		} else {
			pending := make([]string, 0, len(translated))
			for _, name := range translated {
				if !a.aptPackageInstalled(name) {
					pending = append(pending, name)
				}
			}
			if len(pending) == 0 {
				return ExitOK
			}
			translated = pending
		}
		return commandExit(a.run("apt-get", append(command, translated...)...))
	case "remove":
		installed := make([]string, 0, len(translated))
		for _, name := range translated {
			if a.aptPackageInstalled(name) {
				installed = append(installed, name)
			}
		}
		if len(installed) == 0 {
			return ExitOK
		}
		return commandExit(a.run("apt-get", append([]string{"remove", "-y"}, installed...)...))
	case "explicit":
		return commandExit(a.run("apt-mark", append([]string{"manual"}, translated...)...))
	}
	return ExitUsage
}

func (a *App) aptPackageInstalled(name string) bool {
	result := a.query("dpkg-query", "-W", "-f=${Status}\n", name)
	if result.Code != 0 {
		return false
	}
	return strings.Contains(result.Output, "install ok installed")
}

func (a *App) aptPackageAvailable(name string) bool {
	if a.aptPackageInstalled(name) {
		return true
	}
	result := a.query("apt-cache", "policy", name)
	if result.Code != 0 {
		return false
	}
	for _, line := range strings.Split(result.Output, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "Candidate:") {
			cand := strings.TrimSpace(strings.TrimPrefix(trimmed, "Candidate:"))
			return cand != "" && cand != "(none)"
		}
	}
	return false
}

func (a *App) aptCount(foreign bool) int {
	if foreign {
		archRes := a.query("dpkg", "--print-foreign-architectures")
		foreignArchs := strings.Fields(strings.TrimSpace(archRes.Output))
		if len(foreignArchs) == 0 {
			fmt.Fprintln(a.cfg.Stdout, "0")
			return ExitOK
		}
		res := a.query("dpkg-query", "-W", "-f=${Package}:${Architecture}\n")
		if res.Code != 0 {
			return ExitFalse
		}
		archMap := map[string]bool{}
		for _, arch := range foreignArchs {
			archMap[arch] = true
		}
		count := 0
		for _, line := range strings.Split(strings.TrimSpace(res.Output), "\n") {
			parts := strings.Split(line, ":")
			if len(parts) == 2 && archMap[parts[1]] {
				count++
			}
		}
		fmt.Fprintln(a.cfg.Stdout, count)
		return ExitOK
	}
	res := a.query("dpkg-query", "-W", "-f=${Package}\n")
	if res.Code != 0 {
		return ExitFalse
	}
	fmt.Fprintln(a.cfg.Stdout, countLines(res.Output))
	return ExitOK
}

func (a *App) aptOrphans() ([]string, error) {
	result := a.query("apt-get", "--dry-run", "autoremove")
	if result.Code != 0 {
		return nil, fmt.Errorf("apt-get autoremove: exit %d: %s", result.Code, result.Output)
	}
	return parseAptAutoremoveOutput(result.Output), nil
}

func parseAptAutoremoveOutput(output string) []string {
	lines := strings.Split(output, "\n")
	collect := false
	var orphans []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "The following packages will be REMOVED:") {
			collect = true
			continue
		}
		if collect {
			if strings.HasSuffix(trimmed, ":") || strings.HasPrefix(trimmed, "0 upgraded,") || strings.Contains(trimmed, "not upgraded.") {
				break
			}
			fields := strings.Fields(trimmed)
			for _, f := range fields {
				f = strings.TrimSuffix(f, "*")
				if f != "" {
					orphans = append(orphans, f)
				}
			}
		}
	}
	sort.Strings(orphans)
	return orphans
}
