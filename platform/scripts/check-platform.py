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
ARGO_PROJECTS = "platform/argocd/projects"
OBSERVABILITY = "platform/observability"
GITOPS_ROOT = "gitops/environments"
# Order matters: a service enters each environment only through the one before it.
ENVIRONMENTS = ["dev", "staging", "production"]

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

environment_services: dict[str, set[str]] = {}
for environment in ENVIRONMENTS:
    directory = ROOT / GITOPS_ROOT / environment
    environment_services[environment] = {p.stem for p in directory.glob("*.yaml")} if directory.is_dir() else set()

for environment, services in environment_services.items():
    for service in sorted(services):
        where = f"{GITOPS_ROOT}/{environment}/{service}.yaml"
        application = applications.get(f"{service}-{environment}")
        if application is None:
            fail(where, "has no matching Argo CD Application, so nothing deploys it")
            continue
        destination = ((application.get("spec") or {}).get("destination") or {}).get("namespace")
        if destination != f"idp-{environment}":
            fail(f"{ARGO_APPS}/{service}-{environment}", f"deploys to '{destination}' rather than idp-{environment}")
        # An Application that layered another environment's values or state would
        # deploy that environment's configuration under this environment's name.
        body = yaml.safe_dump(application)
        if f"values-{environment}.yaml" not in body or f"{GITOPS_ROOT}/{environment}/{service}.yaml" not in body:
            fail(f"{ARGO_APPS}/{service}-{environment}", f"does not layer values-{environment}.yaml and its own {environment} deployment state")

for earlier, later in zip(ENVIRONMENTS, ENVIRONMENTS[1:]):
    for service in sorted(environment_services[later] - environment_services[earlier]):
        fail(f"{GITOPS_ROOT}/{later}/{service}.yaml", f"exists without {earlier}; a service reaches {later} only through {earlier}")

# Every Application that layers deployment state must point at a file that
# exists, or Argo CD fails the sync with a missing values file.
for name, application in sorted(applications.items()):
    body = yaml.safe_dump(application)
    for referenced in re.findall(r"\$values/(\S+\.yaml)", body):
        if not (ROOT / referenced).is_file():
            fail(f"{ARGO_APPS}/{name}", f"references '{referenced}', which does not exist")

# --- Argo CD projects --------------------------------------------------------

# An Application naming a project that does not exist is rejected by Argo CD at
# sync time, and an Application whose source is outside its project's allow-list
# fails the same way. Both are visible from the files.
projects: dict[str, dict] = {}
projects_dir = ROOT / ARGO_PROJECTS
if not projects_dir.is_dir():
    fail(ARGO_PROJECTS, "is missing")
else:
    for path in sorted(projects_dir.glob("*.yaml")):
        for document in load_all(path):
            if document.get("kind") == "AppProject":
                projects[(document.get("metadata") or {}).get("name", path.stem)] = document

for name, application in sorted(applications.items()):
    spec = application.get("spec") or {}
    project = spec.get("project")
    sources = spec.get("sources") or ([spec["source"]] if spec.get("source") else [])

    if project not in projects:
        fail(f"{ARGO_APPS}/{name}", f"names project '{project}', which is not defined")
    else:
        allowed = set((projects[project].get("spec") or {}).get("sourceRepos") or [])
        for source in sources:
            repo = source.get("repoURL")
            if repo and "*" not in "".join(allowed) and repo not in allowed:
                fail(f"{ARGO_APPS}/{name}", f"uses source '{repo}', which project '{project}' does not allow")

    # Checked regardless of the project: a chart pinned to a range or left
    # floating lets an unreviewed upstream release change the cluster on the
    # next reconciliation, which is a problem on its own terms.
    for source in sources:
        if source.get("chart"):
            revision = str(source.get("targetRevision", ""))
            if not re.fullmatch(r"\d+\.\d+\.\d+", revision):
                fail(f"{ARGO_APPS}/{name}", f"pins chart '{source['chart']}' to '{revision}', which is not an exact version")

# --- observability -----------------------------------------------------------

observability_dir = ROOT / OBSERVABILITY
if observability_dir.is_dir():
    for path in sorted((observability_dir / "manifests").rglob("*.yaml")):
        relative = path.relative_to(ROOT).as_posix()
        for document in load_all(path):
            metadata = document.get("metadata") or {}
            labels = metadata.get("labels") or {}
            # A dashboard is loaded by its label and parsed as JSON. Both are
            # silent failures: no label means no dashboard, and bad JSON means
            # Grafana logs a line nobody reads.
            if document.get("kind") == "ConfigMap" and labels.get("grafana_dashboard"):
                import json as _json
                for key, value in (document.get("data") or {}).items():
                    try:
                        board = _json.loads(value)
                    except ValueError:
                        fail(relative, f"dashboard '{key}' is not valid JSON")
                        continue
                    if not board.get("panels"):
                        fail(relative, f"dashboard '{key}' has no panels")
                    if not board.get("uid"):
                        fail(relative, f"dashboard '{key}' has no uid, so it cannot be linked to")
            if document.get("kind") == "PrometheusRule":
                for group in ((document.get("spec") or {}).get("groups") or []):
                    for rule in group.get("rules") or []:
                        # Recording rules precompute series for alerts to use; they
                        # page nobody, so they need an expression and nothing more.
                        if "record" in rule:
                            if not rule.get("expr"):
                                fail(relative, f"recording rule '{rule['record']}' has no expression")
                            continue
                        alert = rule.get("alert", "<unnamed>")
                        if not rule.get("expr"):
                            fail(relative, f"alert '{alert}' has no expression")
                        annotations = rule.get("annotations") or {}
                        # An alert that fires without saying what to do about it
                        # is a notification, not an alert.
                        for required in ("summary", "runbook_url"):
                            if required not in annotations:
                                fail(relative, f"alert '{alert}' has no {required} annotation")

# --- admission policies ------------------------------------------------------

POLICIES = "platform/security/policies"
POLICY_TEST = "platform/security/tests/kyverno-test.yaml"

policy_names: dict[str, str] = {}
policy_namespaces: set[str] = set()
policies_dir = ROOT / POLICIES
if policies_dir.is_dir():
    for path in sorted(p for p in policies_dir.iterdir() if p.is_file()):
        relative = path.relative_to(ROOT).as_posix()
        for document in load_all(path):
            # Argo CD applies everything in this directory. Anything that is not a
            # policy - a test fixture above all - would be created in the cluster.
            if document.get("kind") != "ValidatingPolicy":
                fail(relative, f"contains a {document.get('kind')}; only ValidatingPolicy belongs in {POLICIES}")
                continue
            name = (document.get("metadata") or {}).get("name", "")
            policy_names[name] = relative
            spec = document.get("spec") or {}
            if "Deny" not in (spec.get("validationActions") or []):
                fail(relative, f"policy '{name}' does not Deny, so it reports violations without preventing them")
            # An unscoped policy also constrains Argo CD, Kyverno and the collectors,
            # and can reject the very components needed to repair it.
            if not (spec.get("matchConstraints") or {}).get("namespaceSelector"):
                fail(relative, f"policy '{name}' has no namespaceSelector, so it would apply to platform namespaces")
            selector = (spec.get("matchConstraints") or {}).get("namespaceSelector") or {}
            governed: set[str] = set()
            selected_namespace = (selector.get("matchLabels") or {}).get("kubernetes.io/metadata.name")
            if selected_namespace:
                governed.add(selected_namespace)
            for expression in selector.get("matchExpressions") or []:
                if expression.get("key") == "kubernetes.io/metadata.name" and expression.get("operator") == "In":
                    governed.update(expression.get("values") or [])
            policy_namespaces.update(governed)
            # A rule staging does not enforce is a rule a release can pass staging
            # while breaking, so every policy must govern every environment.
            for environment in ENVIRONMENTS:
                if f"idp-{environment}" not in governed:
                    fail(relative, f"policy '{name}' does not govern idp-{environment}")
            for index, validation in enumerate(spec.get("validations") or [], start=1):
                if not (validation.get("message") or validation.get("messageExpression")):
                    fail(relative, f"policy '{name}' validation {index} has no message, so a rejection explains nothing")

if policy_names:
    test_path = ROOT / POLICY_TEST
    if not test_path.is_file():
        fail(POLICY_TEST, "is missing, so no admission policy is tested")
    else:
        test = (load_all(test_path) or [{}])[0]
        loaded = {(test_path.parent / p).resolve() for p in test.get("policies") or []}
        outcomes: dict[str, set[str]] = {}
        for result in test.get("results") or []:
            outcomes.setdefault(result.get("policy", ""), set()).add(result.get("result", ""))
        for name, relative in sorted(policy_names.items()):
            if (ROOT / relative).resolve() not in loaded:
                fail(POLICY_TEST, f"does not load {relative}")
            # A policy never shown to fail may never fire; one never shown to pass
            # may be rejecting everything, including the platform's own chart; one
            # never shown to skip has no tested boundary and may be reaching into
            # the platform's own namespaces.
            for expected in ("pass", "fail", "skip"):
                if expected not in outcomes.get(name, set()):
                    fail(POLICY_TEST, f"has no '{expected}' result for policy '{name}'")

# The Kyverno CLI reads namespace labels only from the test's variables file.
# Without an entry for each namespace the policies select, selectors match
# nothing in particular, every namespace is evaluated, and the suite passes while
# proving nothing about scope. It did exactly that before this check existed.
if policy_names and (ROOT / POLICY_TEST).is_file():
    test = (load_all(ROOT / POLICY_TEST) or [{}])[0]
    variables_name = test.get("variables")
    if not variables_name:
        fail(POLICY_TEST, "has no variables file, so the CLI ignores every namespace selector")
    else:
        variables_path = (ROOT / POLICY_TEST).parent / variables_name
        entries = []
        if variables_path.is_file():
            entries = (load_all(variables_path) or [{}])[0].get("namespaceSelector") or []
        declared_namespaces = {entry.get("name") for entry in entries}
        for namespace in sorted(policy_namespaces - declared_namespaces):
            fail(POLICY_TEST, f"declares no labels for namespace '{namespace}', which the policies select on")

# --- identity wiring ---------------------------------------------------------

# Names that must agree across Terraform, Helm values and Argo CD. A mismatch
# fails closed at runtime - a controller or service that runs but can obtain no
# AWS credentials - which is safe, and very slow to diagnose from inside a pod.


def terraform_string(relative: str, pattern: str) -> str | None:
    path = ROOT / relative
    if not path.is_file():
        return None
    match = re.search(pattern, path.read_text(encoding="utf-8"), re.S)
    return match.group(1) if match else None


DEV_VARIABLES = "infrastructure/terraform/environments/dev/variables.tf"
WORKLOAD_IDENTITY = "infrastructure/terraform/environments/dev/workload-identity.tf"
VALUES_DEV = "platform/helm/service/values-dev.yaml"
ESO_VALUES = "platform/security/values/external-secrets.yaml"

cluster_name = terraform_string(DEV_VARIABLES, r'variable "cluster_name"\s*\{.*?default\s*=\s*"([^"]+)"')
eso_account = terraform_string(WORKLOAD_IDENTITY, r'external_secrets_service_account\s*=\s*"([^"]+)"')
eso_namespace = terraform_string(WORKLOAD_IDENTITY, r'external_secrets_namespace\s*=\s*"([^"]+)"')

platform_prefix = terraform_string(DEV_VARIABLES, r'variable "platform_prefix"\s*\{.*?default\s*=\s*"([^"]+)"')
if platform_prefix:
    for environment in ENVIRONMENTS:
        relative = f"platform/helm/service/values-{environment}.yaml"
        if not (ROOT / relative).is_file():
            fail(relative, "is missing, so the environment has no chart configuration")
            continue
        prefix = ((load_all(ROOT / relative) or [{}])[0].get("aws") or {}).get("resourcePrefix")
        expected = f"{platform_prefix}-{environment}"
        if prefix != expected:
            fail(relative, f"aws.resourcePrefix is '{prefix}', but Terraform names this environment's roles and secrets '{expected}'")

if eso_account and (ROOT / ESO_VALUES).is_file():
    account = ((load_all(ROOT / ESO_VALUES) or [{}])[0].get("serviceAccount") or {}).get("name")
    if account != eso_account:
        fail(ESO_VALUES, f"serviceAccount.name is '{account}', but the Pod Identity association binds '{eso_account}'")

eso_application = applications.get("security-external-secrets")
if eso_namespace and eso_application:
    namespace = ((eso_application.get("spec") or {}).get("destination") or {}).get("namespace")
    if namespace != eso_namespace:
        fail(f"{ARGO_APPS}/security-external-secrets", f"installs into '{namespace}', but the Pod Identity association expects '{eso_namespace}'")

# --- promotion history -------------------------------------------------------

# "Passed staging" is a property of a digest, and it is checked here from Git.
# Every digest an environment names must already have been named by the
# environment before it, in an earlier commit that did not also change the later
# environment. A production file edited by hand to a digest staging never ran
# fails this, as does a single change that moves staging and production at once.
import subprocess


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)


def digest_in(text: str) -> str | None:
    match = re.search(r'^  digest: "(sha256:[0-9a-f]{64})"$', text, re.M)
    return match.group(1) if match else None


promotions_checked = 0
inside = git("rev-parse", "--is-inside-work-tree")
if inside.returncode == 0 and inside.stdout.strip() == "true":
    if git("rev-parse", "--is-shallow-repository").stdout.strip() == "true":
        fail(GITOPS_ROOT, "promotion history cannot be checked in a shallow clone; check out with full history")
    else:
        for earlier, later in zip(ENVIRONMENTS, ENVIRONMENTS[1:]):
            for service in sorted(environment_services[later] & environment_services[earlier]):
                later_path = f"{GITOPS_ROOT}/{later}/{service}.yaml"
                earlier_path = f"{GITOPS_ROOT}/{earlier}/{service}.yaml"
                digest = digest_in((ROOT / later_path).read_text(encoding="utf-8"))
                if not digest:
                    continue
                promotions_checked += 1
                proven = False
                for commit in git("log", "--format=%H", "HEAD", "--", earlier_path).stdout.split():
                    touched = git("show", "--name-only", "--format=", commit).stdout.split()
                    if later_path in touched:
                        continue
                    added = git("show", "--format=", commit, "--", earlier_path).stdout.splitlines()
                    if any(line.startswith("+") and digest in line for line in added):
                        proven = True
                        break
                if not proven:
                    fail(later_path, f"runs {digest[:19]}..., which {earlier} never ran on its own first")

# --- documentation links -----------------------------------------------------

# A runbook with a dead link fails during the incident it was written for. Every
# relative link in the documentation must lead to a file that exists. Template
# skeletons are skipped: their links are rendered per service.
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
links_checked = 0
for path in sorted(ROOT.rglob("*.md")):
    relative = path.relative_to(ROOT).as_posix()
    if any(part in {".git", "node_modules", "rendered", "skeleton", "platform-change"} for part in path.parts):
        continue
    text = re.sub(r"```.*?```", "", path.read_text(encoding="utf-8", errors="replace"), flags=re.S)
    for target in LINK.findall(text):
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        file_part = target.split("#", 1)[0]
        if not file_part:
            continue
        links_checked += 1
        if not (path.parent / file_part).exists():
            fail(relative, f"links to '{target}', which does not exist")

# --- report ------------------------------------------------------------------

if problems:
    print(f"{len(problems)} problem(s) found:")
    for problem in problems:
        print(f"  - {problem}")
    sys.exit(1)

print(
    f"OK: {len(entities)} catalog entities, {len(groups)} groups, "
    f"{len(registered)} registered service(s), {len(applications)} Argo CD application(s) "
    f"across {len(projects)} project(s), {len(policy_names)} admission policies, "
    f"{len(ENVIRONMENTS)} environments, {promotions_checked} promotion(s) traced through history, "
    f"{links_checked} documentation links resolved."
)
