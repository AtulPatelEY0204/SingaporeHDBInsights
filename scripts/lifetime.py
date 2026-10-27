#!/usr/bin/env python3
"""Minimal OutSystems LifeTime API v2 client used by the GitHub Actions pipeline.

Standard library only. Authentication is a LifeTime service-account token
(Bearer). Configure with environment variables:

    LT_URL    e.g. https://lifetime.example.com  (no trailing /lifetimeapi)
    LT_TOKEN  service account token (GitHub secret)

Commands
    tag              Tag the applications' current state in an environment as a version
    deploy           Deploy what is running in --source to --target and wait for the result
    current-versions Write {app name: version key} running in an environment (rollback point)
    deploy-versions  Deploy explicit version keys from a JSON file (used for rollback)

Exit code is 0 on success, 1 on a failed/aborted deployment, 2 on usage or API errors.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Callable, Optional

API_PATH = "/lifetimeapi/rest/v2"
FINAL_OK = {"finished_successful", "finished_with_warnings"}
FINAL_BAD = {"finished_with_errors", "aborted"}


class LifeTimeError(RuntimeError):
    pass


class LifeTime:
    def __init__(self, base_url: str, token: str, opener: Optional[Callable] = None, sleep: Callable[[float], None] = time.sleep):
        self.base = base_url.rstrip("/") + API_PATH
        self.token = token
        self._open = opener or urllib.request.urlopen
        self._sleep = sleep

    # ---------- HTTP ----------
    def request(self, method: str, path: str, body=None):
        data = None if body is None else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token)
        req.add_header("Accept", "application/json")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with self._open(req, timeout=120) as resp:
                raw = resp.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:500]
            raise LifeTimeError(f"{method} {path} -> HTTP {e.code}: {detail}") from None
        if not raw:
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw.strip().strip('"')

    # ---------- lookups ----------
    def environment_key(self, name: str) -> str:
        for env in self.request("GET", "/environments") or []:
            if env.get("Name", "").lower() == name.lower():
                return env["Key"]
        raise LifeTimeError(f"Environment '{name}' not found in LifeTime")

    def applications(self) -> list:
        return self.request("GET", "/applications?IncludeModules=false&IncludeEnvStatus=true") or []

    def app_by_name(self, apps: list, name: str) -> dict:
        for app in apps:
            if app.get("Name", "").lower() == name.lower():
                return app
        raise LifeTimeError(f"Application '{name}' not found in LifeTime")

    @staticmethod
    def status_in_env(app: dict, env_key: str) -> dict:
        for st in app.get("AppStatusInEnvs") or []:
            if st.get("EnvironmentKey") == env_key:
                return st
        raise LifeTimeError(f"Application '{app.get('Name')}' is not deployed in the environment")

    # ---------- commands ----------
    def tag(self, env_name: str, app_names: list, version: str, changelog: str) -> dict:
        """Tags each app in env_name. Unmodified apps keep their current version."""
        env_key = self.environment_key(env_name)
        apps = self.applications()
        result = {}
        for name in app_names:
            app = self.app_by_name(apps, name)
            st = self.status_in_env(app, env_key)
            if st.get("IsModified", True):
                key = self.request("POST", f"/environments/{env_key}/applications/{app['Key']}/versions",
                                   {"ChangeLog": changelog, "Version": version, "MobileVersions": []})
                print(f"Tagged {name} {version} in {env_name}: {key}")
            else:
                key = st["BaseApplicationVersionKey"]
                print(f"{name} unchanged in {env_name}; reusing version {key}")
            result[name] = key
        return result

    def current_versions(self, env_name: str, app_names: list) -> dict:
        env_key = self.environment_key(env_name)
        apps = self.applications()
        return {n: self.status_in_env(self.app_by_name(apps, n), env_key)["BaseApplicationVersionKey"] for n in app_names}

    def deploy_versions(self, source_env: str, target_env: str, versions: dict, notes: str, timeout_s: int = 3600) -> str:
        src, tgt = self.environment_key(source_env), self.environment_key(target_env)
        plan = {
            "ApplicationOperations": [{"ApplicationVersionKey": key, "DeleteApplication": False} for key in versions.values()],
            "Notes": notes,
            "SourceEnvironmentKey": src,
            "TargetEnvironmentKey": tgt,
        }
        dep_key = self.request("POST", "/deployments", plan)
        print(f"Created deployment plan {dep_key}: {', '.join(versions)} {source_env} -> {target_env}")
        self.request("POST", f"/deployments/{dep_key}/start/")
        return self.wait(dep_key, timeout_s)

    def deploy(self, source_env: str, target_env: str, app_names: list, notes: str, timeout_s: int = 3600) -> str:
        return self.deploy_versions(source_env, target_env, self.current_versions(source_env, app_names), notes, timeout_s)

    def wait(self, dep_key: str, timeout_s: int) -> str:
        deadline = time.monotonic() + timeout_s
        last_logged = 0
        while True:
            st = self.request("GET", f"/deployments/{dep_key}/status/") or {}
            status = st.get("DeploymentStatus", "unknown")
            log = st.get("DeploymentLog") or []
            for entry in log[last_logged:]:
                print(f"  [{entry.get('Instant', '')}] {entry.get('Message', '')}")
            last_logged = len(log)
            if status in FINAL_OK:
                print(f"Deployment {dep_key}: {status}")
                return status
            if status in FINAL_BAD:
                raise LifeTimeError(f"Deployment {dep_key}: {status}. {st.get('Info', '')}")
            if status == "needs_user_intervention":
                raise LifeTimeError(f"Deployment {dep_key} needs user intervention in LifeTime (e.g. outdated consumers or a conflict). {st.get('Info', '')}")
            if time.monotonic() > deadline:
                raise LifeTimeError(f"Deployment {dep_key} still '{status}' after {timeout_s}s")
            self._sleep(15)


def _apps(value: str) -> list:
    return [a.strip() for a in value.split(",") if a.strip()]


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("tag"); t.add_argument("--env", required=True); t.add_argument("--apps", required=True)
    t.add_argument("--version", required=True); t.add_argument("--changelog", default="Tagged by CI"); t.add_argument("--out")
    d = sub.add_parser("deploy"); d.add_argument("--source", required=True); d.add_argument("--target", required=True)
    d.add_argument("--apps", required=True); d.add_argument("--notes", default="Deployed by CI"); d.add_argument("--timeout", type=int, default=3600)
    c = sub.add_parser("current-versions"); c.add_argument("--env", required=True); c.add_argument("--apps", required=True); c.add_argument("--out", required=True)
    v = sub.add_parser("deploy-versions"); v.add_argument("--source", required=True); v.add_argument("--target", required=True)
    v.add_argument("--versions-file", required=True); v.add_argument("--notes", default="Rollback by CI"); v.add_argument("--timeout", type=int, default=3600)
    args = p.parse_args(argv)

    url, token = os.environ.get("LT_URL"), os.environ.get("LT_TOKEN")
    if not url or not token:
        print("LT_URL and LT_TOKEN must be set", file=sys.stderr)
        return 2
    lt = LifeTime(url, token)
    try:
        if args.cmd == "tag":
            res = lt.tag(args.env, _apps(args.apps), args.version, args.changelog)
            if args.out:
                with open(args.out, "w", encoding="utf-8") as f:
                    json.dump(res, f, indent=2)
        elif args.cmd == "deploy":
            lt.deploy(args.source, args.target, _apps(args.apps), args.notes, args.timeout)
        elif args.cmd == "current-versions":
            with open(args.out, "w", encoding="utf-8") as f:
                json.dump(lt.current_versions(args.env, _apps(args.apps)), f, indent=2)
            print(f"Wrote {args.out}")
        elif args.cmd == "deploy-versions":
            with open(args.versions_file, encoding="utf-8") as f:
                versions = json.load(f)
            lt.deploy_versions(args.source, args.target, versions, args.notes, args.timeout)
    except LifeTimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
