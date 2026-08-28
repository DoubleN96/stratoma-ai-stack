#!/usr/bin/env python3
"""Provision a GTM container with GA4 + Meta Pixel, by API instead of by hand.

Idempotent: tags are matched by name, so re-running updates instead of duplicating.

    export GTM_SA_KEY=/secure/path/service-account.json
    python3 gtm_provision.py --account-id 1234567 --container-id 7654321 \
        --ga4-id G-XXXXXXXXXX --meta-pixel-id 000000000000 --dry-run

Requires: pip install google-api-python-client google-auth
The service account must already be a member of the container with Publish
permission — the API cannot grant itself access. See docs/TRACKING-AND-ANALYTICS.md
"""
import argparse
import os
import sys

SCOPES = [
    "https://www.googleapis.com/auth/tagmanager.edit.containers",
    # creating a version is a separate scope from editing the workspace
    "https://www.googleapis.com/auth/tagmanager.edit.containerversions",
    "https://www.googleapis.com/auth/tagmanager.publish",
]

ALL_PAGES_TRIGGER = "2147479553"  # built-in "All Pages", identical in every container


def ga4_tag(measurement_id):
    """GA4 configuration tag, firing on every page."""
    return {
        "name": "GA4 - Configuration",
        "type": "gaawc",
        "parameter": [
            # "tagId" is what the current API wants; the old "measurementIdOverride"
            # is rejected with "vendorTemplate.parameter.tagId: The value must not be empty."
            {"key": "tagId", "type": "template", "value": measurement_id},
        ],
        "firingTriggerId": [ALL_PAGES_TRIGGER],
    }


def meta_pixel_tag(pixel_id):
    """Meta Pixel base code. Browser side only — pair it with server-side CAPI
    sharing the same event_id, or you lose the conversions ad blockers eat."""
    snippet = (
        "<script>!function(f,b,e,v,n,t,s)"
        "{if(f.fbq)return;n=f.fbq=function(){n.callMethod?"
        "n.callMethod.apply(n,arguments):n.queue.push(arguments)};"
        "if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';"
        "n.queue=[];t=b.createElement(e);t.async=!0;"
        "t.src=v;s=b.getElementsByTagName(e)[0];"
        "s.parentNode.insertBefore(t,s)}(window,document,'script',"
        "'https://connect.facebook.net/en_US/fbevents.js');"
        f"fbq('init','{pixel_id}');fbq('track','PageView');</script>"
    )
    return {
        "name": "Meta Pixel - Base",
        "type": "html",
        "parameter": [
            {"key": "html", "type": "template", "value": snippet},
            {"key": "supportDocumentWrite", "type": "boolean", "value": "false"},
        ],
        "firingTriggerId": [ALL_PAGES_TRIGGER],
    }


def plan(args):
    """The tags this run would create or update. Pure — no network, so it is testable."""
    tags = []
    if args.ga4_id:
        tags.append(ga4_tag(args.ga4_id))
    if args.meta_pixel_id:
        tags.append(meta_pixel_tag(args.meta_pixel_id))
    return tags


def default_workspace(service, container_path):
    workspaces = (
        service.accounts()
        .containers()
        .workspaces()
        .list(parent=container_path)
        .execute()
        .get("workspace", [])
    )
    if not workspaces:
        sys.exit("container has no workspace — create one in the GTM UI first")
    for w in workspaces:
        if w["name"] == "Default Workspace":
            return w["path"]
    return workspaces[0]["path"]


def apply(args, tags):
    from google.oauth2 import service_account
    from googleapiclient.discovery import build

    key = args.key or os.environ.get("GTM_SA_KEY")
    if not key:
        sys.exit("set GTM_SA_KEY or pass --key (path to the service account JSON)")

    creds = service_account.Credentials.from_service_account_file(key, scopes=SCOPES)
    service = build("tagmanager", "v2", credentials=creds, cache_discovery=False)

    container = f"accounts/{args.account_id}/containers/{args.container_id}"
    workspace = default_workspace(service, container)
    api = service.accounts().containers().workspaces().tags()

    existing = {t["name"]: t for t in api.list(parent=workspace).execute().get("tag", [])}

    for tag in tags:
        if tag["name"] in existing:
            api.update(path=existing[tag["name"]]["path"], body=tag).execute()
            print(f"updated: {tag['name']}")
        else:
            api.create(parent=workspace, body=tag).execute()
            print(f"created: {tag['name']}")

    if args.publish:
        version = (
            service.accounts()
            .containers()
            .workspaces()
            .create_version(path=workspace, body={"name": "provisioned by gtm_provision.py"})
            .execute()
        )
        version_path = version["containerVersion"]["path"]
        service.accounts().containers().versions().publish(path=version_path).execute()
        print(f"published: {version_path}")
    else:
        print("not published — changes sit in the workspace. Re-run with --publish.")


def self_check():
    """Runnable check: the payloads must carry the ids and fire on all pages."""
    ga4 = ga4_tag("G-TESTID1234")
    assert ga4["type"] == "gaawc"
    assert any(p["key"] == "tagId" and p["value"] == "G-TESTID1234" for p in ga4["parameter"])
    assert ga4["firingTriggerId"] == [ALL_PAGES_TRIGGER]

    pixel = meta_pixel_tag("111122223333")
    html = next(p["value"] for p in pixel["parameter"] if p["key"] == "html")
    assert "fbq('init','111122223333')" in html
    assert pixel["firingTriggerId"] == [ALL_PAGES_TRIGGER]

    assert len(plan(argparse.Namespace(ga4_id="G-A", meta_pixel_id=None))) == 1
    assert plan(argparse.Namespace(ga4_id=None, meta_pixel_id=None)) == []

    print("self-check ok")


def main():
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--account-id")
    p.add_argument("--container-id")
    p.add_argument("--ga4-id", help="GA4 measurement id, G-XXXXXXXXXX")
    p.add_argument("--meta-pixel-id", help="Meta pixel id, digits only")
    p.add_argument("--key", help="service account JSON (default: $GTM_SA_KEY)")
    p.add_argument("--dry-run", action="store_true", help="print the plan, touch nothing")
    p.add_argument("--publish", action="store_true", help="publish a container version after applying")
    p.add_argument("--self-check", action="store_true", help="verify payload building, no network")
    args = p.parse_args()

    if args.self_check:
        self_check()
        return

    if not (args.ga4_id or args.meta_pixel_id):
        sys.exit("nothing to do: pass --ga4-id and/or --meta-pixel-id")

    tags = plan(args)

    if args.dry_run:
        for tag in tags:
            print(f"would set: {tag['name']} ({tag['type']})")
        return

    if not (args.account_id and args.container_id):
        sys.exit("--account-id and --container-id are required unless --dry-run")

    apply(args, tags)


if __name__ == "__main__":
    main()
