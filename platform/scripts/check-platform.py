#!/usr/bin/env python3
"""Check the catalog, the service template and the service registry.

Backstage reports these problems at runtime, in a portal nobody has opened yet:
an entity owned by a group that does not exist, a template that renders
${{ values.something }} nothing supplies, a skeleton file that ships with its
placeholders intact. Each one is cheap to detect from the files themselves, so
they are detected here instead.

Usage: python3 platform/scripts/check-platform.py [repository root]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - environment problem, not a finding
    sys.exit("PyYAML is required: pip install pyyaml")

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()

CATALOG_FILES = [
    "platform/backstage/catalog/org.yaml",
    "platform/backstage/catalog/systems.yaml",
    "apps/sample-service/catalog-info.yaml",
]
TEMPLATE = "platform/backstage/templates/node-service/template.yaml"
SKELETON = "platform/backstage/templates/node-service/skeleton"
PLATFORM_CHANGE = "platform/backstage/templates/node-service/platform-change"
GITOPS_DEV = "gitops/environments/dev"
ARGO_APPS = "platform/argocd/applications"

# Annotations the platform actually reads. A Component missing one of these
# still appears in the portal, just without the half that makes it useful.
REQUIRED_COMPONENT_ANNOTATIONS = [
    "backstage.io/kubernetes-label-selector",
    "argocd/app-name",
]
OWNED_KINDS = {"Component", "System", "Domain", "Resource", "API", "Template"}
VALUE_REFERENCE = re.compile(r"\$\{\{\s*values\.([A-Za-z_][A-Za-z0-9_]*)")

problems: list[str] = []


def fail(where: str, message: str) -> None:
    problems.append(f"{where}: {message}")


def load_all(path: Path) -> list[dict]:
    try:
        return [d for d in yaml.safe_load_all(path.read_text(encoding="utf-8")) if d]
    except yaml.YAMLError as error:
        fail(path.relative_to(ROOT).as_posix(), f"is not valid YAML ({error.__class__.__name__})")
        return []


# --- catalog -----------------------------------------------------------------

entities: dict[str, dict] = {}
groups: set[str] = set()
systems: set[str] = set()

for relative in CATALOG_FILES:
    path = ROOT / relative
    if not path.is_file():
        fail(relative, "is missing")
        continue
    for entity in load_all(path):
        where = f"{relative}"
        kind = entity.get("kind")
        name = (entity.get("metadata") or {}).get("name")
        if not kind or not name:
            fail(where, "an entity has no kind or no metadata.name")
            continue
        key = f"{kind}:{name}"
        if key in entities:
            fail(where, f"{key} is defined twice")
        entities[key] = entity
        if kind == "Group":
            groups.add(name)
        if kind == "System":
            systems.add(name)

for key, entity in entities.items():
    kind, name = key.split(":", 1)
    where = f"catalog {key}"
    spec = entity.get("spec") or {}
    if kind in OWNED_KINDS:
        owner = spec.get("owner")
        if not owner:
            fail(where, "has no spec.owner")
        elif owner not in groups:
            fail(where, f"is owned by '{owner}', which is not a Group in org.yaml")
    if kind == "Component":
        system = spec.get("system")
        if system and system not in systems:
            fail(where, f"belongs to system '{system}', which does not exist")
        annotations = (entity.get("metadata") or {}).get("annotations") or {}
        for annotation in REQUIRED_COMPONENT_ANNOTATIONS:
            if annotation not in annotations:
                fail(where, f"is missing the '{annotation}' annotation")

# A User whose memberOf names a group that does not exist resolves to nothing,
# and the person quietly owns none of what they think they own.
for key, entity in entities.items():
    if key.startswith("User:"):
        for group in (entity.get("spec") or {}).get("memberOf") or []:
            if group not in groups:
                fail(f"catalog {key}", f"is a member of '{group}', which is not a Group")

# --- template ----------------------------------------------------------------

template_path = ROOT / TEMPLATE
supplied: set[str] = set()
if not template_path.is_file():
    fail(TEMPLATE, "is missing")
else:
    documents = load_all(template_path)
    template = documents[0] if documents else {}
    spec = template.get("spec") or {}
    if not str(template.get("apiVersion", "")).startswith("scaffolder.backstage.io/"):
        fail(TEMPLATE, "is not a scaffolder Template")
    if (template.get("spec") or {}).get("owner") not in groups:
        fail(TEMPLATE, "is owned by a group that is not in org.yaml")

    declared: set[str] = set()
    for section in spec.get("parameters") or []:
        declared.update((section.get("properties") or {}).keys())
        for required in section.get("required") or []:
            if required not in (section.get("properties") or {}):
                fail(TEMPLATE, f"requires '{required}', which it does not declare")

    step_ids: set[str] = set()
    for step in spec.get("steps") or []:
        step_id, action = step.get("id"), step.get("action")
        if not step_id or not action:
            fail(TEMPLATE, "a step has no id or no action")
            continue
        step_ids.add(step_id)
        # Track what each fetch:template step can substitute, so the skeleton
        # can be checked against it rather than against the parameter list.
        if action == "fetch:template":
            supplied.update(((step.get("input") or {}).get("values") or {}).keys())

    for referenced in set(re.findall(r"steps\.([A-Za-z0-9_]+)\.output", template_path.read_text(encoding="utf-8"))):
        if referenced not in step_ids:
            fail(TEMPLATE, f"references the output of step '{referenced}', which does not exist")

    for name in sorted(supplied):
        if name not in declared:
            fail(TEMPLATE, f"passes '{name}' to a skeleton but declares no such parameter")

# --- template content --------------------------------------------------------

for area in (SKELETON, PLATFORM_CHANGE):
    directory = ROOT / area
    if not directory.is_dir():
        fail(area, "is missing")
        continue
    templated_extension = area == SKELETON
    for path in sorted(p for p in directory.rglob("*") if p.is_file()):
        relative = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        referenced = set(VALUE_REFERENCE.findall(text)) | set(VALUE_REFERENCE.findall(path.name))
        for name in sorted(referenced):
            if name not in supplied:
                fail(relative, f"uses values.{name}, which no fetch:template step supplies")
        # Under templateFileExtension only .njk files are rendered. A file that
        # references values without that extension ships its placeholders intact.
        if templated_extension and referenced and path.suffix != ".njk":
            fail(relative, "references values but is not named .njk, so it will not be rendered")
        if templated_extension and path.suffix == ".njk" and not referenced:
            fail(relative, "is named .njk but references no values")

        # YAML in a template is still YAML. Substituting a placeholder for every
        # value lets it be parsed here rather than failing during a scaffold run,
        # when the only evidence is a stack trace in the portal.
        rendered_name = VALUE_REFERENCE.sub("placeholder", path.name).replace("}}", "").strip()
        if rendered_name.endswith((".yaml", ".yml")) or rendered_name.endswith((".yaml.njk", ".yml.njk")):
            probe = VALUE_REFERENCE.sub("placeholder", text)
            probe = re.sub(r"placeholder\s*(\|[^}]*)?\}\}", "placeholder", probe)
            try:
                list(yaml.safe_load_all(probe))
            except yaml.YAMLError as error:
                fail(relative, f"is not valid YAML once rendered ({error.__class__.__name__})")

# --- registry consistency ----------------------------------------------------

gitops_dir = ROOT / GITOPS_DEV
argo_dir = ROOT / ARGO_APPS
registered = {p.stem for p in gitops_dir.glob("*.yaml")} if gitops_dir.is_dir() else set()
applications: dict[str, dict] = {}
if argo_dir.is_dir():
    for path in sorted(argo_dir.glob("*.yaml")):
        for document in load_all(path):
            if document.get("kind") == "Application":
                applications[(document.get("metadata") or {}).get("name", path.stem)] = document

for service in sorted(registered):
    if f"{service}-dev" not in applications:
        fail(f"{GITOPS_DEV}/{service}.yaml", "has no matching Argo CD Application, so nothing deploys it")

# Every Application that layers deployment state must point at a file that
# exists, or Argo CD fails the sync with a missing values file.
for name, application in sorted(applications.items()):
    body = yaml.safe_dump(application)
    for referenced in re.findall(r"\$values/(\S+\.yaml)", body):
        if not (ROOT / referenced).is_file():
            fail(f"{ARGO_APPS}/{name}", f"references '{referenced}', which does not exist")

# --- report ------------------------------------------------------------------

if problems:
    print(f"{len(problems)} problem(s) found:")
    for problem in problems:
        print(f"  - {problem}")
    sys.exit(1)

print(
    f"OK: {len(entities)} catalog entities, {len(groups)} groups, "
    f"{len(registered)} registered service(s), {len(applications)} Argo CD application(s)."
)
