#
# koji integration tests
#


import functools
import unittest
import subprocess


F33_REPO = "http://download.fedoraproject.org/pub/fedora/linux/releases/33/Everything/$arch/os"

RHEL_REPOS = [
    "http://download.devel.redhat.com/released/RHEL-8/8.2.0/BaseOS/x86_64/os/",
    "http://download.devel.redhat.com/released/RHEL-8/8.2.0/AppStream/x86_64/os/",
]

def koji_command(*args, _input=None, _globals=None, **kwargs):
    args = list(args) + [f'--{k}={v}' for k, v in kwargs.items()]
    if _globals:
        args = [f'--{k}={v}' for k, v in _globals.items()] + args
    return subprocess.run(["koji"] + args,
                          encoding="utf-8",
                          stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT,
                          input=_input,
                          check=False)


def parse_os_release():
    info = {}
    with open("/etc/os-release") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line[0] == "#":
                continue
            k, v = line.split("=", 1)
            info[k] = v.strip('"')
    return info


def is_fedora():
    info = parse_os_release()
    return info["ID"].lower() == "fedora"


def is_rhel():
    info = parse_os_release()
    return info["ID"].lower() == "rhel"


class TestIntegration(unittest.TestCase):

    def setUp(self):
        global_args = dict(
            server="http://localhost:8080/kojihub",
            user="kojiadmin",
            password="kojipass",
            authtype="password")
        self.koji = functools.partial(koji_command,
                                      "osbuild-image",
                                      _globals=global_args)

    def check_res(self, res: subprocess.CompletedProcess):
        if res.returncode != 0:
            msg = ("\nkoji FAILED:" +
                   "\n args: [" + " ".join(res.args) + "]" +
                   "\n error: " + res.stdout)
            self.fail(msg)

    def check_fail(self, res: subprocess.CompletedProcess):
        if res.returncode == 0:
            msg = ("\nkoji unexpectedly succeed:" +
                   "\n args: [" + " ".join(res.args) + "]" +
                   "\n error: " + res.stdout)
            self.fail(msg)

    @unittest.skipUnless(is_fedora(), "no cross builds")
    def test_compose_fedora(self):
        """Successful Fedora compose"""
        # Simple test of a successful compose of F33
        # Needs the f33-candidate tag be setup properly

        res = self.koji("Fedora-Cloud",
                        "33",
                        "fedora-33",
                        "f33-candidate",
                        "x86_64",
                        "--wait",
                        repo=F33_REPO)
        self.check_res(res)

    @unittest.skipUnless(is_rhel(), "no cross builds")
    def test_compose_rhel(self):
        """Successful RHEL compose"""
        # Simple test of a successful compose of RHEL

        repos = []
        for repo in RHEL_REPOS:
            repos += ["--repo", repo]

        res = self.koji("RHEL-Cloud",
                        "8",
                        "rhel-8",
                        "f33-candidate",
                        "x86_64",
                        "--wait",
                        *repos)
        self.check_res(res)

    def test_unknown_tag_check(self):
        """Unknown Tag check"""
        # Check building an unknown tag fails
        res = self.koji("Fedora-Cloud",
                        "33",
                        "fedora-33",
                        "UNKNOWNTAG",
                        "x86_64")
        self.check_fail(res)
