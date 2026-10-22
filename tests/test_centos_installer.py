"""Exercise package selection and the generated wrapper without root or networking."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = (ROOT / "amnezia_codex_cli_centos_bx/install.sh").read_text()
BASH = os.environ.get("TEST_BASH") or shutil.which("bash")
PACKAGE_FUNCTION = INSTALLER.split("install_matching_kernel_devel() (", 1)[1].split(
    "\n)\n", 1
)[0]
MOCKS = r'''
set -Eeuo pipefail
ID=centos
NAME="CentOS Stream"
die() { echo "ERROR: $*" >&2; exit 1; }
uname() { echo "${TEST_KERNEL:-5.14.0-669.el9.x86_64}"; }
rpm() {
    if [[ $1 == -qp ]]; then
        echo "${TEST_RPM:-kernel-devel-5.14.0-669.el9.x86_64}"
    else
        [[ -f "$TEST_DIR/installed" ]]
    fi
}
dnf() {
    printf 'dnf %s\n' "$*" >> "$TEST_DIR/calls"
    if [[ $1 == repoquery ]]; then
        [[ $TEST_CASE != repo ]] || echo kernel-devel
        return 0
    fi
    [[ $TEST_CASE != signature && $TEST_CASE != transaction ]] || return 1
    touch "$TEST_DIR/installed"
}
curl() {
    printf 'curl %s\n' "$*" >> "$TEST_DIR/calls"
    [[ $TEST_CASE != missing ]] || return 22
}
'''


class CentosInstallerTests(unittest.TestCase):
    def run_packages(self, case, *, installed=False, extra="", **env):
        with tempfile.TemporaryDirectory() as directory:
            tmp = Path(directory)
            (tmp / "calls").touch()
            if installed:
                (tmp / "installed").touch()
            result = subprocess.run(
                [BASH, "-c", MOCKS + "\n" + extra
                 + "\ninstall_matching_kernel_devel() (" + PACKAGE_FUNCTION
                 + "\n)\ninstall_matching_kernel_devel\n"],
                env={**os.environ, "TEST_DIR": tmp.as_posix(), "TEST_CASE": case, **env},
                text=True, capture_output=True,
            )
            return result, (tmp / "calls").read_text()

    def test_installed_package_needs_no_network(self):
        result, calls = self.run_packages("installed", installed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, "")

    def test_repository_package_preferred(self):
        result, calls = self.run_packages("repo")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dnf install -y kernel-devel-5.14.0-669.el9.x86_64", calls)
        self.assertNotIn("curl", calls)

    def test_missing_repository_package_uses_signed_exact_build(self):
        result, calls = self.run_packages("fallback")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("/5.14.0/669.el9/data/signed/8483c65d/x86_64/", calls)
        self.assertIn("dnf --setopt=localpkg_gpgcheck=1 install -y", calls)

    def test_signature_failure_stops_installation(self):
        result, calls = self.run_packages("signature")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signature checks remain enabled", result.stderr)
        self.assertNotIn("--nogpgcheck", calls)

    def test_missing_signed_build_stops_before_install(self):
        result, calls = self.run_packages("missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("dnf --setopt", calls)

    def test_mismatched_download_rejected(self):
        result, calls = self.run_packages("fallback", TEST_RPM="kernel-devel-5.14.0-758.el9.x86_64")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("dnf --setopt", calls)

    def test_other_distribution_never_uses_centos_rpm(self):
        result, calls = self.run_packages("fallback", extra="ID=rocky")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("curl", calls)

    def test_custom_kernel_never_uses_fallback(self):
        result, calls = self.run_packages("fallback", TEST_KERNEL="6.1.0-custom.x86_64")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("curl", calls)

    def test_repository_transaction_failure_does_not_use_fallback(self):
        result, calls = self.run_packages("repo", extra="""
dnf() {
    if [[ $1 == repoquery ]]; then echo kernel-devel; return 0; fi
    return 1
}
""")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("curl", calls)

    def test_wrapper_forwards_auth_storage_and_user_arguments_inside_vpn(self):
        wrapper = INSTALLER.split("cat > /usr/local/bin/codex <<'SCRIPT'\n", 1)[1].split("\nSCRIPT", 1)[0]
        for args in ([], ["login", "status"], ["exec", "two words"]):
            with self.subTest(args=args):
                # Intercept exec/env as well, so no host commands or network run.
                script = r'''
systemctl() { return 0; }
exec() { "$@"; }
env() {
    while [[ $1 == -u ]]; do unset "$2"; shift 2; done
    "$@"
}
ip() {
    [[ $1 == netns && $2 == exec && $3 == codexvpn ]] || return 91
    shift 3
    [[ $1 != awg ]] || return 0
    "$@"
}
fake_codex() { printf '<%s>\n' "$@"; }
export -f ip fake_codex
'''
                result = subprocess.run(
                    [BASH, "-c", script + wrapper.replace("__REAL_CODEX__", "fake_codex"), "codex", *args],
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(),
                                 ["<-c>", '<cli_auth_credentials_store="file">',
                                  *[f"<{arg}>" for arg in args]])


if __name__ == "__main__":
    unittest.main()
