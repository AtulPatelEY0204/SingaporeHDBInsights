"""Unit tests for scripts/lifetime.py with a fake LifeTime API (no network)."""
import io
import json
import os
import sys
import unittest
import urllib.error

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts"))
import lifetime  # noqa: E402

ENVS = [{"Key": "env-dev", "Name": "Development"}, {"Key": "env-tst", "Name": "Test"}, {"Key": "env-prd", "Name": "Production"}]
APPS = [
    {"Key": "app-core", "Name": "HDB Resale", "AppStatusInEnvs": [
        {"EnvironmentKey": "env-dev", "BaseApplicationVersionKey": "v-core-dev", "IsModified": True},
        {"EnvironmentKey": "env-prd", "BaseApplicationVersionKey": "v-core-prd", "IsModified": False}]},
    {"Key": "app-ui", "Name": "Singapore HDB Insight", "AppStatusInEnvs": [
        {"EnvironmentKey": "env-dev", "BaseApplicationVersionKey": "v-ui-dev", "IsModified": False},
        {"EnvironmentKey": "env-prd", "BaseApplicationVersionKey": "v-ui-prd", "IsModified": False}]},
]


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class FakeLifeTime:
    """Routes requests like the real API and records them."""

    def __init__(self, statuses):
        self.calls = []
        self.statuses = list(statuses)

    def __call__(self, req, timeout=None):
        path = req.full_url.split("/lifetimeapi/rest/v2", 1)[1]
        body = json.loads(req.data) if req.data else None
        self.calls.append((req.get_method(), path, body))
        assert req.headers["Authorization"] == "Bearer tkn"
        if path == "/environments":
            out = ENVS
        elif path.startswith("/applications?"):
            out = APPS
        elif path.endswith("/versions") and req.get_method() == "POST":
            out = "v-new-" + path.split("/")[4]
        elif path == "/deployments":
            out = "dep-1"
        elif path.endswith("/start/"):
            out = None
        elif path.endswith("/status/"):
            status = self.statuses.pop(0)
            if status == "http500":
                raise urllib.error.HTTPError(req.full_url, 500, "boom", {}, io.BytesIO(b"server error"))
            out = {"DeploymentStatus": status, "Info": "info", "DeploymentLog": [{"Instant": "t", "Message": status}]}
        else:
            raise AssertionError("unexpected path " + path)
        return FakeResponse(b"" if out is None else json.dumps(out).encode())


def client(statuses=()):
    fake = FakeLifeTime(statuses)
    return lifetime.LifeTime("https://lt.example.com/", "tkn", opener=fake, sleep=lambda s: None), fake


class LifeTimeTests(unittest.TestCase):
    def test_tag_only_modified_apps(self):
        lt, fake = client()
        res = lt.tag("Development", ["HDB Resale", "Singapore HDB Insight"], "1.2.0", "notes")
        self.assertEqual(res, {"HDB Resale": "v-new-app-core", "Singapore HDB Insight": "v-ui-dev"})
        posts = [c for c in fake.calls if c[0] == "POST"]
        self.assertEqual(len(posts), 1)
        self.assertEqual(posts[0][2], {"ChangeLog": "notes", "Version": "1.2.0", "MobileVersions": []})

    def test_deploy_builds_plan_from_source_versions_and_waits(self):
        lt, fake = client(["running", "running", "finished_with_warnings"])
        status = lt.deploy("Development", "Production", ["HDB Resale", "Singapore HDB Insight"], "rel")
        self.assertEqual(status, "finished_with_warnings")
        plan = next(c[2] for c in fake.calls if c[1] == "/deployments")
        self.assertEqual(plan["SourceEnvironmentKey"], "env-dev")
        self.assertEqual(plan["TargetEnvironmentKey"], "env-prd")
        self.assertEqual([o["ApplicationVersionKey"] for o in plan["ApplicationOperations"]], ["v-core-dev", "v-ui-dev"])
        self.assertIn(("POST", "/deployments/dep-1/start/", None), fake.calls)

    def test_failed_deployment_raises(self):
        lt, _ = client(["running", "finished_with_errors"])
        with self.assertRaises(lifetime.LifeTimeError):
            lt.deploy("Development", "Production", ["HDB Resale"], "rel")

    def test_user_intervention_raises(self):
        lt, _ = client(["needs_user_intervention"])
        with self.assertRaisesRegex(lifetime.LifeTimeError, "user intervention"):
            lt.deploy("Development", "Production", ["HDB Resale"], "rel")

    def test_http_error_is_reported(self):
        lt, _ = client(["http500"])
        with self.assertRaisesRegex(lifetime.LifeTimeError, "HTTP 500"):
            lt.deploy("Development", "Production", ["HDB Resale"], "rel")

    def test_current_versions_is_the_rollback_point(self):
        lt, _ = client()
        self.assertEqual(lt.current_versions("Production", ["HDB Resale", "Singapore HDB Insight"]),
                         {"HDB Resale": "v-core-prd", "Singapore HDB Insight": "v-ui-prd"})

    def test_unknown_names_fail_clearly(self):
        lt, _ = client()
        with self.assertRaisesRegex(lifetime.LifeTimeError, "Environment 'Staging'"):
            lt.environment_key("Staging")
        with self.assertRaisesRegex(lifetime.LifeTimeError, "Application 'Nope'"):
            lt.current_versions("Production", ["Nope"])

    def test_cli_requires_credentials(self):
        os.environ.pop("LT_URL", None)
        os.environ.pop("LT_TOKEN", None)
        self.assertEqual(lifetime.main(["current-versions", "--env", "Production", "--apps", "A", "--out", "x.json"]), 2)


if __name__ == "__main__":
    unittest.main()
